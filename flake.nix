{
  description = "HardCaml Shell with GHC 9.6";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems f;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.autoconf
              pkgs.gmp
              pkgs.pkg-config
              pkgs.zlib
              pkgs.opam
              pkgs.ocaml
              pkgs.dune_3
              pkgs.ocamlformat

              pkgs.haskell.compiler.ghc96
              pkgs.hlint
              pkgs.cabal-install
            ];

            shellHook = ''
              echo "HardCaml Shell"
              echo -n "OCaml:        " && ocamlc -version
              echo -n "Dune:         " && dune --version
              echo -n "ocamlformat:  " && ocamlformat --version
              ghc --version
              hlint --version

              echo "Note: This shell doesn't setup OxCaml or HardCaml. Instructions: https://github.com/janestreet/hardcaml_template_project"

              echo "Run:"
              echo "opam switch 5.2.0+ox"
              echo "eval \$(opam env)"
            '';
          };
        }
      );
    };
}
