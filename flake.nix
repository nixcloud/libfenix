{
  description = "libfenix: Rust toolchains with cargo (libnix), 1.87 and 1.99";

  inputs = {
    # the nixpkgs cargo (libnix) builds with
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      inherit (builtins)
        concatStringsSep
        isAttrs
        ;
      inherit (nixpkgs.lib)
        concatMapAttrs
        genAttrs
        isDerivation
        isFunction
        mapAttrs'
        nameValuePair
        ;

      # the cargo (libnix) releases are built from build systems generated on x86_64-linux
      eachSystem = genAttrs [
        "x86_64-linux"
      ];

      libfenixFor = system: import ./. {
        inherit system;
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      };

      lines = [ "rust-1_87" "rust-1_99" ];

      attrDerivations = set: path: (concatMapAttrs
        (k: v:
          if isDerivation v then
            { ${concatStringsSep "." (path ++ [ k ])} = v; }
          else if isAttrs v then
            attrDerivations v (path ++ [ k ])
          else
            { })
        set);
    in

    {
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      packages = eachSystem (system: concatMapAttrs
        (k: v:
          if isDerivation v then
            { ${k} = v; }
          else if isFunction v then
            {
              ${k} = {
                type = "derivation";
                name = "dummy-function";
                outputName = "dummy-out";
                outputs = [ ];
                __functor = _: v;
              };
            }
          else if isAttrs v then
            (if k == "targets" then
              genAttrs
                (map (x: "targets.<triple>.${x}.rust-std") lines)
                (_: {
                  type = "derivation";
                  name = "dummy-rust-std";
                  outputName = "dummy-out";
                  outputs = [ ];
                })
            else
              attrDerivations v [ k ])
            // {
              ${k} = {
                type = "derivation";
                name = "dummy-attrset";
                outputName = "dummy-out";
                outputs = [ ];
              } // v;
            }
          else v)
        (libfenixFor system));

      devShells = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          libfenix = libfenixFor system;
          shell = line: pkgs.mkShell {
            # nix-prefetch-git: for vendored git dependencies
            packages = [ libfenix.${line}.defaultToolchain pkgs.nix-prefetch-scripts ];
            shellHook = ''
              export CARGO_BACKEND=nix
            '';
          };
        in
        genAttrs lines shell // { default = shell "rust-1_99"; });

      # each toolchain's cargo is the cargo (libnix) release of its rustc's version
      checks = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          libfenix = libfenixFor system;
        in
        genAttrs lines (line:
          let t = libfenix.${line}; in
          pkgs.runCommand "check-libfenix-${line}" { } ''
            ${t.defaultToolchain}/bin/cargo --version | grep -q "^cargo ${t.version} +libnix" \
              || { echo "cargo is not cargo (libnix) ${t.version}" >&2; exit 1; }
            ${t.defaultToolchain}/bin/rustc -V | grep -q "^rustc ${t.version} " \
              || { echo "rustc is not ${t.version}" >&2; exit 1; }
            touch $out
          ''));

      overlays.default = import ./overlay.nix;
    };
}
