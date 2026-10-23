<div id="top">
    <div align="center">
        <img alt='An abstract image of a donut-like object' title='Qezta' height=250 width=250 src='./assets/qezta.gif' style="position: relative; top: 0; right: 0;" />
        <h1 align='center'>infra-nixCfg</h1>
        <strong>My personal declarative Nix configurations for macOS, Android, and Linux (NixOS/WSL).</strong>
    </div>

</div>

---

<div align='center'>
    <a href="https://github.com/DivitMittal/infra-nixCfg/stargazers">
        <img src="https://img.shields.io/github/stars/DivitMittal/infra-nixCfg?&style=for-the-badge&logo=starship&logoColor=white&color=purple" alt="stars"/>
    </a>
    <a href="https://github.com/DivitMittal/infra-nixCfg/">
        <img src="https://img.shields.io/github/repo-size/DivitMittal/infra-nixCfg?&style=for-the-badge&logo=github&logoColor=white&color=purple" alt="size" />
    </a>
    <a href="https://github.com/DivitMittal/infra-nixCfg/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/DivitMittal/infra-nixCfg?&style=for-the-badge&logo=unlicense&logoColor=white&color=purple" alt="license"/>
    </a>
    <a href="https://github.com/nixos/nixpkgs">
        <img src="https://img.shields.io/badge/Nixpkgs-unstable-blue.svg?style=for-the-badge&logo=NixOS&logoColor=white&color=purple" alt="nixpkgs"/>
    </a>
    <img src="https://img.shields.io/github/languages/top/DivitMittal/infra-nixCfg?style=for-the-badge&color=purple" alt="repo-top-language"/>
</div>

---

<div align='center'>
    <a href="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/flake-check.yml">
        <img src="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/.github/workflows/flake-check.yml/badge.svg" alt="nix-flake-check"/>
    </a>
    <a href="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/home-build.yml">
        <img src="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/.github/workflows/home-build.yml/badge.svg" alt="home-manager-build"/>
    </a>
    <a href="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/darwin-build.yml">
        <img src="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/.github/workflows/darwin-build.yml/badge.svg" alt="nix-darwin-build"/>
    </a>
    <a href="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/nixos-build.yml">
        <img src="https://github.com/DivitMittal/infra-nixCfg/actions/workflows/.github/workflows/nixos-build.yml/badge.svg" alt="nixos-build"/>
    </a>
</div>

---

## Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Theme Pipeline](#theme-pipeline)
- [Home Manager Profile Graph](#home-manager-profile-graph)
- [Network Topology](#network-topology)
- [Secrets Management](#secrets-management)
- [Satellite Repositories](#satellite-repositories)

---

## Overview

This repository contains primarily [nix](https://github.com/nixos/nix) configurations, leveraging [Nix Flakes](https://nixos.wiki/wiki/Flakes), [Home Manager](https://github.com/nix-community/home-manager), and system-specific modules ([NixOS](https://nixos.org/), [nix-darwin](https://github.com/LnL7/nix-darwin), [nix-on-droid](https://github.com/nix-community/nix-on-droid)) to achieve a purely declarative, reproducible, and consistent environment across multiple OSes on multiple hosts for multiple users:

- **macOS** (via `nix-darwin`)
- **Android** (via `nix-on-droid`)
- **\*nix (NixOS)** (including WSL via `NixOS-WSL`)

## Quick Start

Drop into a pre-built shell environment without cloning or installing anything:

| Command                                           | Environment                                                            | Platform   |
| ------------------------------------------------- | ---------------------------------------------------------------------- | ---------- |
| `nix run github:DivitMittal/infra-nixCfg#tty`     | Full TTY toolchain (shells, editors, multiplexers, VCS, file tools, …) | all        |
| `nix run github:DivitMittal/infra-nixCfg#desktop` | TTY + Wayland compositor stack (sway, swaybar, mako, …)                | Linux only |

Each command drops you into `$SHELL` with the environment's packages prepended to `PATH`. No activation, no home-manager switch — ephemeral by design.

> The TTY environment already includes the AI toolchain via [ai-nixCfg](https://github.com/DivitMittal/ai-nixCfg).
> For an AI-only shell use `nix run github:DivitMittal/ai-nixCfg#ai`.

---

## Architecture

Every host — NixOS, nix-darwin, nix-on-droid, ISO, or standalone home-manager — is built by a single universal function `mkCfg` (`flake/mkCfg.nix`). It dispatches by `class` to the right configuration builder, then composes a layered module bundle: universal defaults from `common/all/`, platform defaults from `common/hosts/<class>/`, host-specific overrides from `hosts/<class>/<name>/`, and (for home-manager configs) user-domain modules from `home/<domain>/`.

```mermaid
flowchart LR
  subgraph inputs["Flake inputs"]
    direction TB
    np[nixpkgs]
    hm[home-manager]
    nd[nix-darwin]
    nod[nix-on-droid]
    sty[stylix]
    sec["infra-nixCfg-secrets<br/>(private)"]
    more["…+15 more"]
  end

  subgraph layers["Module layers"]
    direction TB
    L1["<b>common/all/</b><br/>shared by every config"]
    L2["<b>common/hosts/&lt;class&gt;/</b><br/>platform defaults"]
    L3["<b>hosts/&lt;class&gt;/&lt;name&gt;/</b><br/>per-host overrides"]
    L4["<b>home/&lt;domain&gt;/</b><br/>home-manager modules"]
    L1 --> L2 --> L3
    L1 --> L4
  end

  mkCfg(["<b>flake/mkCfg.nix</b><br/>universal builder"])

  subgraph outs["Flake outputs"]
    direction TB
    O1[nixosConfigurations]
    O2[darwinConfigurations]
    O3[nixOnDroidConfigurations]
    O4[homeConfigurations]
  end

  inputs --> mkCfg
  layers --> mkCfg
  mkCfg --> outs
```

`mkCfg` is class-driven; each class picks a different system builder and a different slice of modules. See [`flake/README.md`](./flake/README.md) for the dispatch flowchart and [`common/README.md`](./common/README.md) for the override hierarchy.

---

## Project Structure

The repository is organized using [flake-parts](https://github.com/hercules-ci/flake-parts) for better modularity.

```
.
├── flake/      # flake-parts modules — mkCfg, devshells, checks, actions, topology
├── common/     # shared layers: all/, home/, hosts/{all,darwin,droid,iso,nixos}/
├── hosts/      # per-host overrides: darwin/L1, nixos/{L2,T2,WSL}, droid/M1, iso/
├── home/       # home-manager modules by domain: tty/ gui/ tools/ media/ comms/ dev/ web/
├── modules/    # reusable NixOS/HM/darwin modules
├── overlays/   # nixpkgs overlays (custom, customDarwin)
├── pkgs/       # derivations: custom/ and darwin/
├── lib/        # custom Nix utility functions (palette, scanPaths, …)
├── utils/      # rebuild wrapper scripts
├── templates/  # flake templates (vanilla)
├── assets/     # topology SVGs, wallpapers, profile graph
└── flake.nix   # entry point — inputs, nixConfig, flake-parts wiring
```

## Theme Pipeline

A single source-of-truth palette (`lib/palette.nix`) — pitch-black background, neon cyan/magenta accents, soft white-blue foreground — feeds every themed surface in the repo. Stylix consumes it at three layers (home-manager / NixOS / nix-darwin) and theming-aware modules pull from it directly.

```mermaid
flowchart LR
  palette[("<b>lib/palette.nix</b><br/>16-color base16 +<br/>fonts + opacity + wallpaper")]

  palette --> sHome["common/home/stylix.nix"]
  palette --> sNixos["common/hosts/nixos/stylix.nix"]
  palette --> sDarwin["common/hosts/darwin/stylix.nix"]
  palette --> wezterm["home/gui/emulators/wezterm.nix"]

  sHome --> aHome["bat · btop · fzf · gtk · qt<br/>firefox · helix · fish · mako<br/>sway · swaybar · i3status-rust<br/>swaylock · …all stylix targets"]
  sNixos --> aNixos["TTY console · GDM/SDDM<br/>plymouth · system GTK"]
  sDarwin --> aDarwin["nix-darwin system bits"]
  wezterm --> aWezterm["generated cyberpunk.toml<br/>consumed by term-nixCfg"]
```

See [`lib/README.md`](./lib/README.md) for the palette structure and how to retune it.

## Home Manager Profile Graph

This dependency graph visualizes the dependencies of the Home-Manager profile configuration:

![Home Manager Profile Dependency Graph](./assets/home_graph.png)

## Network Topology

The network topology visualizations are automatically generated using [nix-topology](https://github.com/oddlama/nix-topology) and provide a comprehensive view of the infrastructure setup across all hosts and networks.

### Main Topology

Complete view of all nodes, networks, and their interconnections:

![Main Network Topology](./assets/topology/main.svg)

### Network View

Focused visualization of network segments and connectivity:

![Network Topology View](./assets/topology/network.svg)

> **Note**: These topology diagrams are automatically built and updated via GitHub Actions whenever topology configurations.

## Secrets Management

Secrets (API keys, passwords, sensitive configurations) are managed via [agenix](https://github.com/ryantm/agenix) or specificaly [ragenix](https://github.com/yaxitech/ragenix).

1.  Secrets are encrypted using `ssh` keys. My public key is explicitly available to `ragenix`.
2.  The encrypted files reside in a **private** GitHub repository: `DivitMittal/infra-nixCfg-secrets`. This repository is referenced as a flake input.
3.  During the Nix build process, `agenix` decrypts these files using my private key.
4.  The decrypted files are placed in the Nix store & symlinked to their target locations.

⚠️ **Building this configuration requires access to the private `DivitMittal/infra-nixCfg-secrets` repo and the corresponding [age](https://github.com/FiloSottile/age) private `ssh` key.**

## Satellite Repositories

- [DivitMittal/ai-nixCfg](https://github.com/DivitMittal/ai-nixCfg): AI/LLM tool configurations extracted for modularity (CLI tools, cloud services, MCP servers, REPL configurations).
- [DivitMittal/quant-nixCfg](https://github.com/DivitMittal/quant-nixCfg): Experimental sandbox + Nix home-manager modules/packages for open-source algo trading and quant workflows.
- [DivitMittal/playbooks-4-windows](https://github.com/DivitMittal/playbooks-4-windows): Ansible IaC for the Windows 11 boot on the x86_64 MacBook (triple-boot partner of L1 & T2); manages Scoop/Winget/MSYS2 packages, registry, and dotfiles.
- `DivitMittal/infra-nixCfg-secrets`: (Private) Contains encrypted secrets managed by `agenix` & `ragenix`.
- [DivitMittal/Vim-Cfg](https://github.com/DivitMittal/Vim-Cfg): Pure lua standalone Neovim configuration, deployed via `nix4nvchad`.
- [DivitMittal/Emacs-Cfg](https://github.com/DivitMittal/Emacs-Cfg): An elisp doomemacs configuration, used as an input via `nix-doom-emacs-unstraightened`.
- [DivitMittal/TLTR](https://github.com/DivitMittal/TLTR): Cross-platform complex multi-layer keyboard layout tailored for programmers.
- [DivitMittal/hammerspoon-nix](https://github.com/DivitMittal/hammerspoon-nix): A nix home-manager module for hammerspoon & my hammerspoon lua configuration.
- [DivitMittal/firefox-nixCfg](https://github.com/DivitMittal/firefox-nixCfg): A personal nix home-manager module/configurations for firefox.
- [DivitMittal/tidalcycles-nix](https://github.com/DivitMittal/tidalcycles-nix): A nix flake for TidalCycles live coding environment.
- [DivitMittal/term-nixCfg](https://github.com/DivitMittal/term-nixCfg): Terminal emulator configuration.
- [DivitMittal/forge-tofu](https://github.com/DivitMittal/forge-tofu): Terraform configurations for managing the GitHub organization infrastructure.

<div align="right">

[![][back-to-top]](#top)

</div>

[back-to-top]: https://img.shields.io/badge/-BACK_TO_TOP-151515?style=flat-square&color=purple
