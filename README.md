# libfenix

libfenix is [fenix](https://github.com/nix-community/fenix) for [cargo (libnix)](https://github.com/nixcloud/cargo): the
Rust toolchains of the versions cargo (libnix) has releases for, each with the cargo (libnix) release of exactly that
version as its `cargo`. Everything else (rustc, rust-std, clippy, rustfmt, rust-src, rust-analyzer, …) is the rust-lang
dist component, packaged as fenix does.

It is a fork of fenix (MPL-2.0, kept); the toolchain packaging (`lib/mk-toolchain.nix`, `lib/combine.nix`) and the API
are fenix's, restricted to two pinned versions.

| attribute | rustc / dist manifest | cargo |
|---|---|---|
| `rust-1_87` | 1.87.0 (2025-05-15) | cargo (libnix) [`libnix-1.87.0+v4`](https://github.com/nixcloud/cargo/releases/tag/libnix-1.87.0%2Bv4) |
| `rust-1_99`, `latest` | 1.99.0 (2026-10-01) | cargo (libnix) [`libnix-1.99.0+v1`](https://github.com/nixcloud/cargo/releases/tag/libnix-1.99.0%2Bv1) |

There are no channels (stable, beta, nightly) and no dated toolchains: a toolchain needs a cargo (libnix) release of
its version. Other versions, dates or channels fail with an error naming the supported ones.

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

Each toolchain set has what a fenix channel has:

* the components: `rustc` (with rust-std), `cargo` (cargo (libnix)), `clippy`, `rustfmt`, `rust-src`, `rust-analyzer`, …
* `toolchain` (all components), `minimalToolchain`, `defaultToolchain`, `completeToolchain` (rustup's profiles)
* `withComponents [ "rustc" "cargo" "rust-src" ]`
* `cargo-vanilla`: the dist cargo of that version
* `version` (`"1.99.0"`), `libnixRelease` (`"libnix-1.99.0+v1"`)

And as in fenix:

```nix
libfenix.toolchainOf { channel = "1.99"; }                 # or "1.99.0"
libfenix.fromToolchainFile { dir = ./.; }                 # rust-toolchain(.toml) with channel 1.87 or 1.99
libfenix.fromToolchainName { name = "1.87.0"; }
libfenix.combine [ libfenix.rust-1_99.rustc libfenix.rust-1_99.cargo libfenix.targets.wasm32-unknown-unknown.rust-1_99.rust-std ]
```

The overlay adds `pkgs.libfenix`.

## Differences to fenix

* `cargo` is cargo (libnix), built from the release's generated nix build system with the dist rustc/cargo of the same
  version; `combine` keeps it a symlink (fenix's `patchelf --set-rpath $out/lib` would drop its rpath, e.g. libssl)
* rustc ≥ 1.90 on x86_64-linux links with its own lld, past nix's ld wrapper (binaries without rpath). The combined
  `rustc`/`rustdoc` of these versions pass `-C linker-features=-lld`, as cargo (libnix) needs
* x86_64-linux only: the release build systems were generated there, and cargo (libnix) is developed and tested there
* removed: the stable/beta/nightly channels, `fromManifest`/`fromManifestFile`, rust-analyzer nightly and its vscode
  extension, the update bots

## Adding a version

1. a cargo (libnix) release of that version exists (`libnix-<version>+v<n>`)
2. add its manifest hash to `update` and run it: `data/<version>.json`
3. add the release (tag, tarball hashes, cargo unit name) to `lib/releases.nix` and the version to `versions` in
   `default.nix`, and its attribute to `lines` in `flake.nix`
4. `nix flake check`
