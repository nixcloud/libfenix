{ pkgs, lib }:

# The cargo (libnix) release of each supported toolchain (as in the flake.nix of nixcloud/cargo's master-libnix).
#
# A toolchain gets it prebuilt, like fenix gets the dist components: `source` is a release asset of nixcloud/cargo,
# `cargo-<tag>-x86_64-unknown-linux-gnu.tar.xz`, in the rust-installer layout of the dist cargo tarball, which
# mk-toolchain.nix fetches, installs and patchelfs. Nothing is compiled.
#
# `fromSource` builds the release from source: the generated nix build system of the release tarball builds the
# cargo sources of its tag with the vanilla rustc/cargo of the same version. `asset` packs that build into the
# release asset (the dist cargo tarball with its binary replaced, without store paths: no RUNPATH, the FHS
# interpreter); its hash is `assetSha256`. `toolchain` is the vanilla toolchain set (mk-toolchain.nix) of that version.

let
  release = { tag, assetSha256, buildsystemSha256, srcSha256, unit }: toolchain:
    let
      tagUrl = lib.replaceStrings [ "+" ] [ "%2B" ] tag;
      triple = "x86_64-unknown-linux-gnu";
      assetName = "cargo-${tag}-${triple}";

      # "libnix-1.99.0+v3" -> "1.99.0"
      version = lib.head (lib.splitString "+" (lib.removePrefix "libnix-" tag));

      fromSource =
        let
          buildsystem = builtins.fetchTarball {
            url = "https://github.com/nixcloud/cargo/releases/download/${tagUrl}/${tag}.tar.bz2";
            sha256 = buildsystemSha256;
          };
          src = builtins.fetchTarball {
            url = "https://github.com/nixcloud/cargo/archive/refs/tags/${tagUrl}.tar.gz";
            sha256 = srcSha256;
          };
          # built as the releases are (master-libnix's nixLd): rustc >= 1.90 links with the cc's ld (the toolchain's
          # wrapped ld.lld would link the same binary differently), so `asset` reproduces the uploaded file. Only the
          # host is built here, so the flag (stable on x86_64-unknown-linux-gnu only) is fine
          rustc =
            if lib.versionAtLeast version "1.90" then
              pkgs.symlinkJoin
                {
                  name = "rustc-${version}-nix-ld";
                  paths = [ toolchain.rustc ];
                  nativeBuildInputs = [ pkgs.makeWrapper ];
                  postBuild = ''
                    for b in rustc rustdoc; do wrapProgram $out/bin/$b --add-flags "-C linker-features=-lld"; done
                  '';
                }
            else toolchain.rustc;
        in
        (import (buildsystem + "/derivations/default.nix") {
          inherit pkgs rustc;
          cargo = toolchain.cargo-vanilla or toolchain.cargo;
          project_root = src;
          external_crate_dependencies = import (buildsystem + "/Cargo.dependencies.nix") { inherit pkgs; };
        }).${unit};

      asset = pkgs.runCommand "${assetName}.tar.xz"
        {
          src = (toolchain.cargo-vanilla or toolchain.cargo).src;
          nativeBuildInputs = [ pkgs.patchelf pkgs.nukeReferences ];
        } ''
        tar xf $src
        mv cargo-*-${triple} ${assetName}
        bin=${assetName}/cargo/bin/cargo
        install -m755 $(realpath ${fromSource}/bin/cargo) $bin
        patchelf --remove-rpath --set-interpreter /lib64/ld-linux-x86-64.so.2 $bin
        # the old RUNPATH and interpreter stay as unused strings in .dynstr
        nuke-refs $bin
        if grep -aoE '${builtins.storeDir}/[0-9a-z]{32}' $bin | grep -qv '/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee$'; then
          echo "$bin refers to the nix store" >&2
          exit 1
        fi
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -cf - ${assetName} | xz -T1 -9 > $out
      '';
    in
    {
      url = "https://github.com/nixcloud/cargo/releases/download/${tagUrl}/${assetName}.tar.xz";
      sha256 = assetSha256;
      pname = "cargo-libnix";
      version = lib.removePrefix "libnix-" tag;
      # cargo (libnix) links libssl dynamically, the dist cargo statically
      extraRpath = "${pkgs.openssl.out}/lib:${pkgs.stdenv.cc.cc.lib}/lib";
      passthru = { libnixRelease = tag; inherit fromSource asset; };
    };
in
{
  "1.87.0" = release {
    tag = "libnix-1.87.0+v6";
    assetSha256 = "03zapasf8qvv3qh3bz3q9l3arb69ni1h09msxqfk78r77nxddsxv";
    buildsystemSha256 = "sha256:1fqc257xjywbs475512lmf2pnjj6kgh8bfxnspzbnhrpc0xbs8vz";
    srcSha256 = "sha256:1vhkxl0pby6n06257bmlzl9iyk79hsndcys5m5wk2vjswrqsjfql";
    unit = "cargo-0_88_0-bin-d7e8a77a599efbea";
  };

  "1.99.0" = release {
    tag = "libnix-1.99.0+v3";
    assetSha256 = "0xl86y860vk2pv6dnjhhhh3drq4h274386ccrp5qsvji43n14n0x";
    buildsystemSha256 = "sha256:1qqagxk4i0ixrnmv7g9hmgv51vk2nz9x12kivgkfwmx1s3lxb5mq";
    srcSha256 = "sha256:08kriapilxskjfxg3pnsk731hzvm8czzhjw9r1mhzqxz3bslj2hd";
    unit = "cargo-0_100_0-bin-463824861cef8abc";
  };
}
