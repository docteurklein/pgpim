{
  description = "pgpim";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages.pg_duckdb = pkgs.stdenv.mkDerivation rec {
          pname = "pg_duckdb";
          version = "0.1";

          src = pkgs.fetchgit {
            # owner = "duckdb";
            # repo = pname;
            url = "https://github.com/duckdb/pg_duckdb.git";
            rev = "d4ca222cf16653ca72657e0c464362cec85f4a66";
            hash = "sha256-ub0qFK1stUpUY/3fndK8fk4WsBE72hQm1phZZGJqoeU=";
            # deepClone = true;
            # fetchSubmodules = true;
            leaveDotGit = true;
          };

          buildInputs = with pkgs; [ postgresql_16 gcc git gnumake cmake ninja openssl ];

          # patches = [ ./patch_nix ];

          dontConfigure = true;
          buildPhase = ''
            touch .depend
            make install
          '';
          installPhase = ''
            install -D -t $out/lib pg_duckdb${pkgs.postgresql.dlSuffix}
            install -D -t $out/share/postgresql/extension *.sql
            install -D -t $out/share/postgresql/extension *.control
          '';
        };
        devenv.shells.default = {
          name = "pgpim";

          imports = [
          ];

          # https://devenv.sh/reference/options/
          packages = with pkgs; [
            postgresql_16
          ];

          services.postgres = {
            enable = true;
            package = pkgs.postgresql_16;
            initialDatabases = [{
              name = "pgpim";
              schema = ./src/schema.sql;
            }];
            extensions = extensions: [
              extensions.wal2json
              self'.packages.pg_duckdb
            ];
            settings = {
              "wal_level" = "logical";
              "app.tenant" = "tenant#1";
              "shared_preload_libraries" = "auto_explain";
              "auto_explain.log_min_duration" = "500ms";
              "auto_explain.log_nested_statements" = true;
              "auto_explain.log_timing" = true;
              "auto_explain.log_analyze" = true;
              "auto_explain.log_triggers" = true;
            };
          };
        };
      };
    };
}
