let
  inherit (builtins)
    currentSystem elemAt filter fromJSON mapAttrs match readFile;

  getFlake = name:
    with (fromJSON (readFile ./flake.lock)).nodes.${name}.locked; {
      inherit rev;
      outPath = fetchTarball {
        url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
        sha256 = narHash;
      };
    };
in

{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { localSystem = { inherit system; }; }
, lib ? pkgs.lib
}:

# libfenix: fenix for cargo (libnix). The toolchains of the Rust versions cargo (libnix) has releases for (1.87.0,
# 1.99.0), each with the cargo (libnix) release of that version in place of the dist cargo (`cargo-vanilla`). There
# are no channels (stable, beta, nightly): a toolchain needs a cargo (libnix) release of exactly its version.

let
  inherit (lib)
    attrNames attrVals concatMapStringsSep filterAttrs findFirst foldl importJSON importTOML mapAttrs'
    nameValuePair pathIsRegularFile replaceStrings unique zipAttrsWith;

  v = pkgs.stdenv.buildPlatform.rust.rustcTarget;

  combine' = pkgs.callPackage ./lib/combine.nix { };

  mkToolchain = pkgs.callPackage ./lib/mk-toolchain.nix { };

  releases = import ./lib/releases.nix { inherit pkgs lib; };

  # the supported versions: their channel manifests (`./update`), by version and short name
  versions = [ "1.87.0" "1.99.0" ];
  manifests = lib.genAttrs versions (version: importJSON (./data + "/${version}.json"));
  # "1.99.0" -> "rust-1_99"
  attrName = version: "rust-" + replaceStrings [ "." ] [ "_" ] (lib.versions.majorMinor version);
  # "1.99", "1.99.0" -> "1.99.0"
  fullVersion = channel:
    findFirst (version: channel == version || channel == lib.versions.majorMinor version)
      (throw "libfenix supports the toolchains ${concatMapStringsSep ", " lib.versions.majorMinor versions} only (cargo (libnix) has releases for these), not '${channel}'")
      versions;

  fromManifest' = target: suffix: manifest: cargo:
    let
      toolchain = mkToolchain suffix {
        inherit (manifest) date;
        inherit cargo;
        components = mapAttrs
          (_: src: { inherit (src) url; sha256 = src.hash; })
          (filterAttrs (_: src: src ? available && src.available) (mapAttrs
            (_: pkg: pkg.target."*" or pkg.target.${target} or null)
            manifest.pkg));
      };
    in
    toolchain // mapAttrs'
      (k: v:
        nameValuePair "${k}Toolchain" (toolchain.withComponents
          (filter (component: toolchain ? ${component}) v)))
      manifest.profiles
    // {
      inherit manifest;
    };

  # a supported version for `target`: the prebuilt cargo (libnix) of that version for the build platform (it runs
  # there; `cargo.fromSource` builds it with the dist toolchain). Other targets only provide what cross compiling needs
  # from them (rust-std)
  toolchainFor = target: version:
    let
      suffix = "-${version}";
      manifest = manifests.${version};
      vanilla = fromManifest' v suffix manifest null;
      cargo = releases.${version} vanilla;
    in
    fromManifest' target suffix manifest (if target == v then cargo else null) // {
      inherit version;
      libnixRelease = cargo.passthru.libnixRelease;
    };

  toolchains = lib.listToAttrs (map (version: nameValuePair (attrName version) (toolchainFor v version)) versions);

  # like fenix's `toolchainOf`, for a supported version; the manifest is pinned (data/), so there is no root, date or
  # sha256 to give
  toolchainOf' = target:
    { channel ? throw "libfenix: toolchainOf needs a channel, one of ${concatMapStringsSep ", " lib.versions.majorMinor versions}"
    , ...
    } @ args:
    if args ? root || args ? date then
      throw "libfenix: toolchainOf only takes a channel; the toolchains are pinned to the cargo (libnix) releases"
    else
      toolchainFor target (fullVersion channel);

  fromToolchainName' = target: name:
    lib.mapNullable
      (matches:
        let target' = elemAt matches 5; in
        if elemAt matches 3 != null then
          throw "libfenix: '${name}': the toolchains are pinned to the cargo (libnix) releases, no dates"
        else
          toolchainOf' (if target' == null then target else target') { channel = elemAt matches 0; })
      (match
        "^(stable|beta|nightly|[[:digit:]]+\\.[[:digit:]]+(\\.[[:digit:]]+)?)(-([[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}))?(-([-[:alnum:]]+))?\n?$"
        name);

  fromToolchainFile' = target:
    { file ? null, dir ? null, ... }:
    let
      text = readFile (if file == null && dir != null then
        findFirst pathIsRegularFile
          (throw "No rust toolchain file found in ${dir}")
          [ (dir + "/rust-toolchain") (dir + "/rust-toolchain.toml") ]
      else if file != null && dir == null then
        file
      else
        throw "One and only one of `file` and `dir` should be specified");
      toolchain = fromToolchainName' target text;
    in
    if toolchain == null then
      let t = (fromTOML text).toolchain; in
      if t ? path then
        throw "libfenix doesn't support toolchain.path"
      else
        let toolchain = fromToolchainName' target t.channel; in
        combine' "rust-${t.channel}" (attrVals
          (filter (component: toolchain ? ${component}) (unique
            (toolchain.manifest.profiles.${t.profile or "default"}
              ++ t.components or [ ])))
          toolchain ++ map
          (target: (toolchainFor target toolchain.version).rust-std)
          (t.targets or [ ]))
    else
      toolchain.defaultToolchain;

  # rust-std of each target, per version
  targetToolchains = version:
    mapAttrs
      (target: _: { ${attrName version} = toolchainFor target version; })
      manifests.${version}.pkg.rust-std.target;
in

toolchains // rec {
  # the newest supported version
  latest = toolchains.${attrName (lib.last versions)};

  combine = combine' "rust-mixed";

  toolchainOf = toolchainOf' v;

  fromToolchainFile = fromToolchainFile' v;

  fromToolchainName = { name, ... }: fromToolchainName' v name;

  targets =
    mapAttrs
      (target: v:
        v // {
          toolchainOf = toolchainOf' target;
          fromToolchainFile = fromToolchainFile' target;
          fromToolchainName = { name, ... }: fromToolchainName' target name;
        })
      (zipAttrsWith (_: foldl (x: y: x // y) { }) (map targetToolchains versions));
}
