{
  description = "OCaml Shell";

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
            ];

            shellHook = ''
              echo "OCaml Shell"
              echo -n "OCaml:        " && ocamlc -version
              echo -n "Dune:         " && dune --version
              echo -n "ocamlformat:  " && ocamlformat --version
            '';
          };
        }
      );
    };
}
