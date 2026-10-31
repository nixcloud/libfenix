# libfenix

libfenix is [fenix](https://github.com/nix-community/fenix) for [cargo (libnix)](https://github.com/nixcloud/cargo): the
Rust toolchains of the versions cargo (libnix) has releases for, each with the cargo (libnix) release of exactly that
version as its `cargo`. Everything else (rustc, rust-std, clippy, rustfmt, rust-src, rust-analyzer, …) is the rust-lang
dist component, packaged as fenix does.

It is a fork of fenix (MPL-2.0, kept); the toolchain packaging (`lib/mk-toolchain.nix`, `lib/combine.nix`) and the API
are fenix's, restricted to two pinned versions.

| attribute | rustc / dist manifest | cargo |
|---|---|---|
| `rust-1_87` | 1.87.0 (2025-05-15) | cargo (libnix) [`libnix-1.87.0+v5`](https://github.com/nixcloud/cargo/releases/tag/libnix-1.87.0%2Bv5) |
| `rust-1_99`, `latest` | 1.99.0 (2026-10-01) | cargo (libnix) [`libnix-1.99.0+v2`](https://github.com/nixcloud/cargo/releases/tag/libnix-1.99.0%2Bv2) |

There are no channels (stable, beta, nightly) and no dated toolchains: a toolchain needs a cargo (libnix) release of
its version. Other versions, dates or channels fail with an error naming the supported ones.

![a phoenix looking at a rustacean](./libfenix.png)

## A temporary placeholder

libfenix is meant to be temporary. It gives cargo (libnix) toolchains in a fenix shape while cargo (libnix) is young.
Once cargo (libnix) gains more traction, the plan is to merge this work into upstream
[fenix](https://github.com/nix-community/fenix), e.g. as a cargo (libnix) option for its toolchains, and to retire
libfenix. The changes against fenix are listed in [Differences to fenix](#differences-to-fenix).

## Usage

As a flake:

```nix
{
  inputs.libfenix.url = "github:nixcloud/libfenix";

  outputs = { self, libfenix }: {
    devShells.x86_64-linux.default = libfenix.devShells.x86_64-linux.rust-1_99;
    packages.x86_64-linux.toolchain = libfenix.packages.x86_64-linux.rust-1_99.defaultToolchain;
  };
}
```

```sh
nix develop github:nixcloud/libfenix             # 1.99, CARGO_BACKEND=nix
nix develop github:nixcloud/libfenix#rust-1_87
```

Nothing is built: rustc and the other components come from static.rust-lang.org, cargo (libnix) from its
nixcloud/cargo release, all patched for nix like fenix does.

Each toolchain set has what a fenix channel has:

* the components: `rustc` (with rust-std), `cargo` (cargo (libnix)), `clippy`, `rustfmt`, `rust-src`, `rust-analyzer`, …
* `toolchain` (all components), `minimalToolchain`, `defaultToolchain`, `completeToolchain` (rustup's profiles)
* `withComponents [ "rustc" "cargo" "rust-src" ]`
* `cargo-vanilla`: the dist cargo of that version
* `version` (`"1.99.0"`), `libnixRelease` (`"libnix-1.99.0+v2"`)

And as in fenix:

```nix
libfenix.toolchainOf { channel = "1.99"; }                 # or "1.99.0"
libfenix.fromToolchainFile { dir = ./.; }                 # rust-toolchain(.toml) with channel 1.87 or 1.99
libfenix.fromToolchainName { name = "1.87.0"; }
libfenix.combine [ libfenix.rust-1_99.rustc libfenix.rust-1_99.cargo libfenix.targets.wasm32-unknown-unknown.rust-1_99.rust-std ]
```

The overlay adds `pkgs.libfenix`.

## Differences to fenix

* `cargo` is cargo (libnix), prebuilt like the dist components: a release asset of nixcloud/cargo
  (`cargo-<tag>-x86_64-unknown-linux-gnu.tar.xz`, the dist cargo tarball with the cargo (libnix) binary), fetched,
  installed and patchelfed by `lib/mk-toolchain.nix`; nothing is compiled. Its rpath also has openssl and libgcc (it
  links libssl dynamically, the dist cargo statically), and `combine` keeps it a symlink (fenix's
  `patchelf --set-rpath $out/lib` would drop that rpath)
* `cargo.fromSource` builds the release from source: its generated nix build system with the dist rustc/cargo of the
  same version. `cargo.asset` packs that build into the release asset (no RUNPATH, the FHS interpreter, no store
  paths), reproducibly, so `nix build .#rust-1_99.cargo.asset` gives the file the toolchain downloads
* rustc ≥ 1.90 on x86_64-linux links with its own lld (`cc -fuse-ld=lld -B<sysroot>/gcc-ld`), past nix's ld wrapper:
  binaries without rpath, missing e.g. libssl.so.3. As in rust-overlay
  ([#171](https://github.com/oxalica/rust-overlay/pull/171)), the bundled `gcc-ld/ld.lld` of `rustc` goes through
  nixpkgs' `ld-wrapper.sh`, which adds the rpaths like nix's ld (the unwrapped one is in `gcc-ld-unwrapped/`). No rustc
  flag is involved, so cross compiling works as with fenix: wasm32 links with `rust-lld`, musl with the cc and its own
  crt, neither through `gcc-ld/ld.lld`. (`-C linker-features=-lld`, the other fix, is stable on
  `x86_64-unknown-linux-gnu` only and makes `rustc --target wasm32-unknown-unknown` fail)
* cross compiling: combine the toolchain with the targets' std, e.g. for wasm-pack
  `libfenix.combine [ libfenix.rust-1_99.minimalToolchain libfenix.targets.wasm32-unknown-unknown.rust-1_99.rust-std ]`
* x86_64-linux only: the release build systems were generated there, and cargo (libnix) is developed and tested there
* removed: the stable/beta/nightly channels, `fromManifest`/`fromManifestFile`, rust-analyzer nightly and its vscode
  extension, the update bots

## Adding a version

1. a cargo (libnix) release of that version exists (`libnix-<version>+v<n>`)
2. add its manifest hash to `update` and run it: `data/<version>.json`
3. add the release (tag, tarball hashes, cargo unit name, `assetSha256 = lib.fakeSha256`) to `lib/releases.nix` and
   the version to `versions` in `default.nix`, and its attribute to `lines` in `flake.nix` and `update`
4. run `update` again: it builds the release asset from source, pins its hash in `lib/releases.nix` and prints where
   to upload it (the release of the tag on nixcloud/cargo, as `cargo-<tag>-x86_64-unknown-linux-gnu.tar.xz`)
5. `nix flake check`
