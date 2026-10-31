{ callPackage, fetchurl, lib, path, stdenv, zlib, curl, makeBinaryWrapper }:

suffix:
{ date, components, cargo ? null }:

let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    attrVals maintainers mapAttrs' nameValuePair optionals optionalAttrs optionalString
    platforms removeSuffix;

  combine = callPackage ./combine.nix { };
  rpath' = "${zlib}/lib:$out/lib";

  # libfenix: a source can add to the rpath (cargo (libnix) links libssl dynamically) and name its package
  mkComponent = component: source:
    let rpath = rpath' + optionalString (source ? extraRpath) ":${source.extraRpath}"; in
    stdenv.mkDerivation {
      pname = source.pname or "${component}${suffix}";
      version = source.version or source.date or date;
      src = fetchurl { inherit (source) url sha256; };
      passthru = source.passthru or { };

      # the @...@ of the ld-wrapper.sh the bundled ld.lld goes through (see below), as nix's bintools wrapper sets them
      env = optionalAttrs (component == "rustc" && stdenv.hostPlatform.isLinux) {
        inherit (stdenv.cc.bintools) expandResponseParams shell suffixSalt wrapperName coreutils_bin rm mktemp;
        hardening_unsupported_flags = "";
        darwinMinVersion = "";
        fallback_sdk = "";
      };

      nativeBuildInputs = optionals (component == "rustfmt-preview" && stdenv.hostPlatform.isDarwin) [
        makeBinaryWrapper
      ];

      installPhase = ''
        patchShebangs install.sh
        CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

        rm $out/lib/rustlib/{components,install.log,manifest-*,rust-installer-version,uninstall.sh} || true

        ${optionalString stdenv.hostPlatform.isLinux ''
          if [ -d $out/bin ]; then
            for file in $(find $out/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath ${rpath} \
                  "$file" || true
              fi
            done
          fi

          if [ -d $out/lib ]; then
            for file in $(find $out/lib -type f); do
              if isELF "$file"; then
                patchelf --set-rpath ${rpath} "$file" || true
              fi
            done

            for file in $(find $out/lib -path '*/bin/*' -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath ${stdenv.cc.cc.lib}/lib:${rpath} \
                  "$file" || true
              fi
            done
          fi

          if [ -d $out/libexec ]; then
            for file in $(find $out/libexec -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath ${rpath} \
                  "$file" || true
              fi
            done
          fi

          ${optionalString (component == "llvm-tools-preview") ''
            for file in $out/lib/rustlib/*/bin/*; do
              patchelf \
                --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                --set-rpath $out/lib/rustlib/*/lib \
                "$file" || true
            done
          ''}
        ''}

        ${optionalString (component == "rustc") ''
          ${optionalString stdenv.hostPlatform.isDarwin ''
            if [ -e $out/lib/libLLVM.dylib ]; then
              for dir in $out/lib/rustlib/*-apple-darwin; do
                if [ -d "$dir/bin" ] && [ ! -e "$dir/lib/libLLVM.dylib" ]; then
                  mkdir -p "$dir/lib"
                  ln -s $out/lib/libLLVM.dylib "$dir/lib/libLLVM.dylib"
                fi
              done
            fi
          ''}
          ${optionalString stdenv.hostPlatform.isLinux ''
            # libfenix: since 1.90 rustc links with its own lld on x86_64-linux (`cc -fuse-ld=lld -B<sysroot>/gcc-ld`),
            # which bypasses the ld wrapper of nix's cc: no rpath for the -L directories (e.g. openssl), the binaries
            # miss their libraries at runtime. As rust-overlay does (oxalica/rust-overlay#171): the bundled ld.lld goes
            # through nixpkgs' ld-wrapper.sh, the unwrapped one moves next to it (it is a wrapper itself, the name
            # matters). Other targets don't link through gcc-ld/ld.lld (wasm: rust-lld, musl: cc with its own crt),
            # so they need no flag and stay as they are
            wrap() {
              local dst="$1"
              local wrapper="$2"
              export prog="$3"
              export use_response_file_by_default=0
              substituteAll "$wrapper" "$dst"
              chmod +x "$dst"
            }

            dsts=( $out/lib/rustlib/*/bin/gcc-ld/ld.lld )
            if [ -e "''${dsts[0]}" ]; then
              mkdir -p $out/nix-support
              substituteAll ${path}/pkgs/build-support/wrapper-common/utils.bash $out/nix-support/utils.bash
              substituteAll ${path}/pkgs/build-support/wrapper-common/darwin-sdk-setup.bash $out/nix-support/darwin-sdk-setup.bash
              substituteAll ${path}/pkgs/build-support/bintools-wrapper/add-flags.sh $out/nix-support/add-flags.sh
              substituteAll ${path}/pkgs/build-support/bintools-wrapper/add-hardening.sh $out/nix-support/add-hardening.sh
              for dst in "''${dsts[@]}"; do
                unwrapped="$(dirname "$dst")-unwrapped/ld.lld"
                mkdir -p "$(dirname "$unwrapped")"
                mv "$dst" "$unwrapped"
                wrap "$dst" ${path}/pkgs/build-support/bintools-wrapper/ld-wrapper.sh "$unwrapped"
              done
            fi
          ''}
        ''}

        ${optionalString (component == "cargo") ''
          ${optionalString stdenv.hostPlatform.isDarwin ''
            install_name_tool \
              -change "/usr/lib/libcurl.4.dylib" "${curl.out}/lib/libcurl.4.dylib" \
              $out/bin/cargo || true
          ''}
        ''}
          
        ${optionalString (component == "miri-preview") ''
          ${optionalString stdenv.hostPlatform.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/miri || true
          ''}
          ${optionalString stdenv.hostPlatform.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib $out/bin/miri || true
          ''}
        ''}

        ${optionalString (component == "rls-preview") ''
          ${optionalString stdenv.hostPlatform.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/rls || true
          ''}
          ${optionalString stdenv.hostPlatform.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib $out/bin/rls || true
          ''}
        ''}

        ${optionalString (component == "rustfmt-preview") ''
          ${optionalString stdenv.hostPlatform.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/rustfmt || true
          ''}
          ${
            # error: install_name_tool: changing install names or rpaths can't be redone
            # because larger updated load commands do not fit (the program must be relinked)
            optionalString stdenv.hostPlatform.isDarwin ''
              wrapProgram $out/bin/rustfmt \
                --prefix DYLD_LIBRARY_PATH : ${toolchain.rustc}/lib
            ''
          }
        ''}

        ${optionalString (component == "rust-analyzer-preview") ''
          ${optionalString stdenv.hostPlatform.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib $out/bin/rust-analyzer || true
          ''}
          ${optionalString stdenv.hostPlatform.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib $out/bin/rust-analyzer || true
          ''}
        ''}
      '';
      dontStrip = true;
      meta = {
        maintainers = with maintainers; [ figsoda ];
        platforms = platforms.all;
      };
    };

  # libfenix: the cargo (libnix) release of this version (`cargo`, a source like the manifest's) in place of the
  # dist cargo, in every combination (toolchain, profiles, withComponents); the dist cargo stays available as
  # cargo-vanilla
  withLibnix = cargo != null && components ? cargo;

  toolchain = mapAttrs mkComponent (components // optionalAttrs withLibnix { inherit cargo; });

  toolchain' = toolchain // {
    toolchain = combine "rust${suffix}-${date}"
      (attrValues (removeAttrs toolchain [ "rustc-dev" ]));
  } // optionalAttrs (toolchain ? rustc) {
    rustc = combine "rust${suffix}-with-std-${date}"
      (with toolchain; [ rustc rust-std ]) // {
      unwrapped = toolchain.rustc;
    };
    rustc-unwrapped = toolchain.rustc;
  } // optionalAttrs (toolchain ? clippy-preview) {
    clippy-preview = combine "clippy${suffix}-with-std-${date}"
      (with toolchain; [ clippy-preview rustc rust-std ]) // {
      unwrapped = toolchain.clippy-preview;
    };
    clippy-preview-unwrapped = toolchain.clippy-preview;
    clippy-unwrapped = toolchain.clippy-preview;
  } // optionalAttrs (toolchain ? miri-preview) {
    miri-preview = combine "clippy${suffix}-with-src-${date}"
      (with toolchain; [ miri-preview rustc rust-src ]) // {
      unwrapped = toolchain.miri-preview;
    };
    miri-preview-unwrapped = toolchain.miri-preview;
    miri-unwrapped = toolchain.miri-preview;
  };

  toolchain'' = toolchain' // mapAttrs' (k: nameValuePair (removeSuffix "-preview" k)) toolchain';
in

toolchain'' // optionalAttrs withLibnix {
  cargo-vanilla = mkComponent "cargo" components.cargo;
} // {
  withComponents = componentNames: combine
    "rust${suffix}-with-components-${date}"
    (attrVals componentNames toolchain'');
}
