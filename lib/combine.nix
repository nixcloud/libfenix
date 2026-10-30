{ lib, symlinkJoin, stdenv, rustc, makeWrapper }:

let
  inherit (lib) maintainers optionalString platforms;
in

name: paths:

symlinkJoin {
  inherit name paths;
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    for file in $(find $out/bin -xtype f -maxdepth 1); do
      # cargo (libnix) is built by nix, with the rpath of its libraries (libssl, …), which `--set-rpath $out/lib`
      # would replace: stays a symlink
      if [[ $file =~ /cargo$ ]]; then
        continue
      fi

      install -m755 $(realpath "$file") $out/bin

      if [[ $file =~ /rustfmt$ ]]; then
        continue
      fi

      ${optionalString stdenv.hostPlatform.isLinux ''
        if isELF "$file"; then
          patchelf --set-rpath $out/lib "$file" || true
        fi
      ''}

      ${optionalString stdenv.hostPlatform.isDarwin ''
        install_name_tool -add_rpath $out/lib "$file" || true
      ''}
    done

    for file in $(find $out/lib -name "librustc_driver-*"); do
      install $(realpath "$file") "$file"
    done

    ${optionalString (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64) ''
      # since 1.90 rustc links with its own lld on x86_64-linux, which bypasses the ld wrapper of nix's cc: no rpath,
      # the binaries miss their libraries (e.g. libssl.so.3). cargo (libnix) builds with -C linker-features=-lld (as
      # its releases do). Wrapped here, in the combined toolchain: the sysroot (rust-std) is found next to the binary.
      # Only the binary itself: a combination of combined toolchains (defaultToolchain of the combined rustc) copies
      # the wrapper, which already passes the flag
      if [ -x $out/bin/rustc ] && isELF $out/bin/rustc; then
        minor=$($out/bin/rustc -V | sed -n 's/^rustc 1\.\([0-9]*\)\..*/\1/p')
        if [ -n "$minor" ] && [ "$minor" -ge 90 ]; then
          for b in rustc rustdoc; do
            if [ -x $out/bin/$b ]; then
              wrapProgram $out/bin/$b --add-flags "-C linker-features=-lld"
            fi
          done
        fi
      fi
    ''}
  '';
  meta = {
    maintainers = with maintainers; [ figsoda ];
    platforms = platforms.all;
  };
  passthru = {
    targetPlatforms = rustc.targetPlatform or lib.platforms.all;
    tier1TargetPlatforms = rustc.tier1TargetPlatforms or lib.platforms.all;
    badTargetPlatforms = rustc.badTargetPlatforms or [ ];
  };
}
