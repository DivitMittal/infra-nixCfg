_: {
  flake.templates = {
    vanilla = {
      path = ./vanilla;
      description = ''        A personal-preferred flake-parts based nix flake template with
                - nixpkgs (Unstable)
                - actions-nix (GitHub/GitLab CI configuration via nix)
                - treefmt-nix (Multi-language code formatting via `nix fmt`)
                - pre-commit-hooks (Git pre-commit-hooks checks via `nix flake check`)
                - devshells (Ephemeral project-level development environment)
                - customLib (A custom library of nix functions from infra-nixCfg)
                - direnv-nix support (Activation of devshell via direnv)
      '';
    };
  };
}
