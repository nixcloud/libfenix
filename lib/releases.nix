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
        in
        (import (buildsystem + "/derivations/default.nix") {
          inherit pkgs;
          rustc = toolchain.rustc;
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
    tag = "libnix-1.87.0+v5";
    assetSha256 = "16gg6a4jmn1mbbyr1jgg836m3hcdppd7xmc36aqxih4bl98ixz86";
    buildsystemSha256 = "sha256:0k5265x6x5618yvx44qlg6z1rmc0k76g9fj82pmyiacazr8nh7zd";
    srcSha256 = "sha256:16qcm28k3q3cwwv5g49fiic2bicws5s060yaz8x34g9jn0imsbzs";
    unit = "cargo-0_88_0-bin-d7e8a77a599efbea";
  };

  "1.99.0" = release {
    tag = "libnix-1.99.0+v2";
    assetSha256 = "1q4lg720ybl65j9xjj1687pkimgrhy7yaajg8rya2d5nbn6gfj35";
    buildsystemSha256 = "sha256:0v10kxslf5140wd5b14anc79n9c0lkz5yv2y0ni1vxxbzzmadh35";
    srcSha256 = "sha256:1p7llhf5kl2yqr5zcdya81nfr63lsn3iysyc8r827rabz4b8lfg4";
    unit = "cargo-0_100_0-bin-463824861cef8abc";
  };
}
