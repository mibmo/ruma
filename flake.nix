{
  description = "Rust crates for interacting with the Matrix chat network";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-analyzer-src.follows = "";
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, crane, fenix, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          inherit (pkgs) lib;

          craneLib = crane.lib.${system};
          src = craneLib.cleanCargoSource (craneLib.path ./crates/ruma);

          commonArgs = {
            inherit src;
            cargoToml = ./crates/ruma/Cargo.toml;
            cargoVendorDir = null;

            strictDeps = true;

            buildInputs = with pkgs; [
              pkg-config
              openssl
            ] ++ lib.optionals pkgs.stdenv.isDarwin [
              libiconv
            ];
          };

          # @TODO: get toolchain for `rustup-toolchain.toml`
          craneLibLLvmTools = craneLib.overrideToolchain
            (fenix.packages.${system}.complete.withComponents [
              "cargo"
              "llvm-tools"
              "rust-src"
              "rustc"
            ]);

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {

          checks = {
            # Run clippy (and deny all warnings) on the workspace source,
            # again, reusing the dependency artifacts from above.
            #
            # Note that this is done as a separate derivation so that
            # we can block the CI if there are issues here, but not
            # prevent downstream consumers from building our crate by itself.
            ruma-clippy = craneLib.cargoClippy (commonArgs // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });
            ruma-doc = craneLib.cargoDoc (commonArgs // { inherit cargoArtifacts; });
            ruma-fmt = craneLib.cargoFmt (commonArgs // {
              rustfmtExtraArgs = "--all";
            });
            ruma-deny = craneLib.cargoDeny (commonArgs // { });

            # Run tests with cargo-nextest
            # Consider setting `doCheck = false` on other crate derivations
            # if you do not want the tests to run twice
            ruma-nextest = craneLib.cargoNextest (commonArgs // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            });
          };

          devShells.default = craneLib.devShell {
            checks = self.checks.${system};

            packages = with pkgs; [
              cargo-sort
            ];
          };
        });
}
