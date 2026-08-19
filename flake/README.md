# Flake Directory

Flake-parts modules defining flake outputs.

## `mkCfg` Class Dispatch

Every host configuration flows through `mkCfg.nix`. It accepts `{hostName, class, system, …}` and returns the right kind of system (NixOS toplevel, darwin system, droid activationPackage, or home-manager activationPackage), with a class-specific module bundle merged in.

```mermaid
flowchart TB
  call(["<b>mkCfg { hostName; class; system; additionalModules; … }</b>"])
  call --> sw{class?}

  sw -->|nixos| nx["lib.nixosSystem<br/>+ nix-topology + disko"]
  sw -->|darwin| dw["nix-darwin.lib.darwinSystem<br/>+ darwinModules.default"]
  sw -->|droid| dr["nix-on-droid.lib.nixOnDroidConfiguration"]
  sw -->|home| hm["home-manager.lib.homeManagerConfiguration<br/>+ homeManagerModules.default"]
  sw -->|iso| iso["lib.nixosSystem<br/>+ installer/cd-dvd module"]

  subgraph bundle["Composed module bundle"]
    direction TB
    b1["common/all/* — every class<br/>(skipped for droid; only hostSpec.nix)"]
    b2["common/hosts/all/* — non-home, non-droid"]
    b3["common/hosts/&lt;class&gt;/* — class-specific"]
    b4["hosts/&lt;class&gt;/&lt;hostName&gt;/* — host-specific"]
    b5["common/home/* — home only"]
    b6["additionalModules — caller-supplied"]
  end

  nx --> bundle
  dw --> bundle
  dr --> bundle
  hm --> bundle
  iso --> bundle
```

The pkgs handed to each config is extended with `master` / `stable` channels (and, for home configs, `nur` + `brew-nix` on Darwin) so modules can opt into newer or older nixpkgs on a per-package basis.

## Contents

- **apps.nix** - Runnable flake app outputs (`tty`, `desktop` shells)
- **checks.nix** - Pre-commit hooks
- **devshells.nix** - Development environment (`nix develop`)
- **formatters.nix** - Code formatting (`nix fmt`: alejandra, deadnix, statix)
- **iso-packages.nix** - ISO build packages
- **mkCfg.nix** - Universal host builder (nixos/darwin/droid/home)
- **openwrt-images.nix** - OpenWrt/ImmortalWrt multi-PPPoE router images for T1 (x86_64-linux only, see `hosts/README.md`)
- **topology.nix** - Infrastructure visualization (nix-topology)
- **actions/** - GitHub Actions workflows
  - default.nix - Actions module exports
  - darwin-build.nix - macOS build actions
  - flake-check.nix - Flake validation
  - flake-lock-update.nix - Dependency updates
  - home-build.nix - Home-manager builds
  - nixos-build.nix - NixOS build actions
  - topology-build.nix - Topology generation

## Adding Modules

Create `.nix` file using flake-parts structure:

```nix
{inputs, ...}: {
  perSystem = {pkgs, system, ...}: {
    # Configuration
  };
}
```

Auto-imported via `scanPaths`.
