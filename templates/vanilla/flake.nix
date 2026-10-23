{
  description = "{project-name} flake";

  outputs = inputs: let
    inherit (inputs.flake-parts.lib) mkFlake;
    isX86Darwin = system: system == "x86_64-darwin";
  in
    mkFlake {inherit inputs;} ({inputs, ...}: {
      systems = import inputs.systems;
      imports = [(inputs.import-tree ./flake)];
      perSystem = {system, ...}: {
        _module.args.pkgs =
          if isX86Darwin system
          then import inputs."nixpkgs-2605" {inherit system;}
          else import inputs.nixpkgs {inherit system;};
      };
    });

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    "nixpkgs-2605".url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs-2605";
    };
    actions-nix = {
      url = "github:nialov/actions.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs-2605";
        flake-parts.follows = "flake-parts";
        git-hooks.follows = "git-hooks";
      };
    };
    infra-nixCfg = {
      url = "github:DivitMittal/infra-nixCfg";
      flake = false;
    };
  };
}
