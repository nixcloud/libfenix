{ pkgs, lib }:

# The cargo (libnix) release of each supported toolchain (as in the flake.nix of nixcloud/cargo's master-libnix): the
# generated nix build system of the release tarball builds the cargo sources of its tag with the vanilla rustc/cargo
# of the same version. `toolchain` is the vanilla toolchain set (mk-toolchain.nix) of that version.

let
  release = { tag, buildsystemSha256, srcSha256, unit }: toolchain:
    let
      tagUrl = lib.replaceStrings [ "+" ] [ "%2B" ] tag;
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
      inherit (toolchain) rustc cargo;
      project_root = src;
      external_crate_dependencies = import (buildsystem + "/Cargo.dependencies.nix") { inherit pkgs; };
    }).${unit} // { libnixRelease = tag; };
in
{
  "1.87.0" = release {
    tag = "libnix-1.87.0+v4";
    buildsystemSha256 = "sha256:0zhj8sl05g861c7pkwgd1ij26mf68qj1flbad2ivwj113vac9chq";
    srcSha256 = "sha256:0lm951801chcdnjni4068jjwlzyf94byjgjk5qzlr9vihsp5i3ym";
    unit = "cargo-0_88_0-bin-8cad88ffd54a16db";
  };

  "1.99.0" = release {
    tag = "libnix-1.99.0+v1";
    buildsystemSha256 = "sha256:1mwxjyr9ccbq71p1mq296xvs2b10kxb159a90dh3w6wbgs5qizg4";
    srcSha256 = "sha256:03fywzj68mj56m1lis3ghjn4i35kjd8frfkydlwldn8y6a87qviv";
    unit = "cargo-0_100_0-bin-463824861cef8abc";
  };
}
