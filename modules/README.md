# Modules Directory

Reusable NixOS and Home Manager module library shared across the fleet.

## Structure

```
modules/
├── home/         # Home-manager modules
├── hosts/        # NixOS/nix-darwin modules
└── default.nix
```

## Purpose

Reusable configurations with:

- Enable/disable options
- Type checking and validation
- Abstract interfaces for complex setups

## Basic Structure

```nix
{config, lib, pkgs, ...}:
with lib; {
  options.my.module = {
    enable = mkEnableOption "my module";
    option = mkOption {
      type = types.str;
      default = "value";
    };
  };

  config = mkIf config.my.module.enable {
    # Configuration
  };
}
```

## Usage

```nix
{
  imports = [ ../modules/home/my-module.nix ];
  my.module.enable = true;
}
```

Create modules for reusable multi-host configs; use host configs for host-specific settings.
