# Overlays Directory

Nixpkgs overlay layer that provides the platform's custom package set to every configuration.

## Structure

```
overlays/
├── default.nix       # Main overlay composition (flake-parts module)
└── custom.nix        # Custom package overlays
```

## Exports

The `custom` overlay provides:

- `customDarwin` - macOS-specific packages from `../pkgs/darwin/`
- `custom` - General custom packages from `../pkgs/custom/`

All packages are loaded recursively using `packagesFromDirectoryRecursive`.

## Implementation

Custom packages are defined in `custom.nix` using `packagesFromDirectoryRecursive` for automatic discovery.

## Usage

Auto-applied to all systems. Access custom packages via:

```nix
pkgs.customDarwin.myMacPackage
pkgs.custom.myGeneralPackage
```

Use overlays for system-wide changes; use host configs for host-specific packages.
