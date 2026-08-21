---
description: Project-wide knowledge base for the infra-nixCfg multi-platform Nix flake
applyTo: "**"
---

# PROJECT KNOWLEDGE BASE

## OVERVIEW

Multi-platform Nix flake (flake-parts) covering darwin, NixOS/WSL, nix-on-droid, and standalone home-manager. Universal builder `mkCfg` wires common modules, platform layers, and host overrides; heavy auto-import via `lib.custom.scanPaths`.

## STRUCTURE

```
./
├── flake/            # flake-parts modules, mkCfg, actions, topology, devshells, formatters, checks
├── hosts/            # platform hosts (darwin, nixos, droid, iso, wsl)
├── home/             # home-manager modules by domain (tty/gui/tools/media/comms/dev/web)
├── common/           # shared layers (all, home, hosts/{all,darwin,droid,iso,nixos})
├── modules/          # reusable HM & darwin modules
├── overlays/         # custom package overlays (custom, customDarwin)
├── pkgs/             # derivations (custom + darwin binaries)
├── utils/            # rebuild scripts + shared shell helpers
├── openspec/         # project docs
└── assets/           # topology and diagrams
```

## WHERE TO LOOK

| Task              | Location                                     | Notes                                                    |
| ----------------- | -------------------------------------------- | -------------------------------------------------------- |
| Build/CI          | .github/workflows, flake/actions             | Cachix + magic-nix-cache; per-platform builds            |
| Host add/modify   | flake/mkCfg.nix, hosts/\*                    | mkCfg class switch; scanPaths auto-import                |
| Home modules      | home/\*, common/home                         | Drop-in via scanPaths; platform subdirs under gui/       |
| Packages/overlays | overlays/custom.nix, pkgs/\*                 | packagesFromDirectoryRecursive; darwin binaries separate |
| Scripts           | utils/\*.sh                                  | Shared functions in common.sh; tags successful builds    |
| Secrets           | common/all/hostSpec.nix (from private input) | Needs OS-nixCfg-secrets + SSH key                        |

## CODE MAP (key files)

| Symbol/File | Type        | Location                | Role                                                     |
| ----------- | ----------- | ----------------------- | -------------------------------------------------------- |
| flake.nix   | flake entry | flake.nix               | Defines inputs (17+), perSystem, imports major dirs      |
| mkCfg       | function    | flake/mkCfg.nix         | Universal builder for classes nixos/darwin/droid/home    |
| scanPaths   | helper      | lib/custom.nix          | Auto-imports modules in dir (excludes default.nix)       |
| hostSpec    | data        | common/all/hostSpec.nix | User/host identity pulled from secrets input             |
| devshell    | config      | flake/devshells.nix     | Provides hms/hts, LSPs, formatters                       |
| overlays    | overlay     | overlays/custom.nix     | Exposes pkgs.custom/customDarwin via recursive discovery |

## CONVENTIONS

- Auto-import everywhere: `imports = lib.custom.scanPaths ./.;` (implicit module discovery).
- Flake-parts mkFlake; pkgs not memoized to keep overlays flexible.
- allowUnfree=true; allowUnsupportedSystem=false.
- Nullable package options common in modules (mkPackageOption nullable=true).
- Separate macOS binaries in pkgs/darwin; cross-platform in pkgs/custom.

## ANTI-PATTERNS (project-specific)

- Do NOT edit WeeChat configs by hand (warnings in home/comms/irc/weechat/conf/\*).
- tmux.conf.local: obey DO NOT markers (no TPM lines, don't write below markers).
- Shell.nix exists only for bootstrap; prefer flake devshell.

## UNIQUE STYLES

- Universal mkCfg for four classes; layered common → platform → host → user.
- Network topology auto-generated (flake/topology, assets/topology/\*, workflow topology-build).
- AI tooling directories (.claude, .serena) at root; openspec docs separate.

## COMMANDS

```bash
nix develop               # enter devshell (hms/hts available)
hms -v --show-trace       # rebuild/switch home-manager
hts -v --show-trace       # rebuild/switch host (nixos/darwin/droid)
nix fmt                   # treefmt (alejandra, deadnix, statix, prettier, shfmt)
nix flake check           # full flake checks
./utils/home_rebuild.sh   # home rebuild wrapper
./utils/hosts_rebuild.sh  # host rebuild wrapper
```

## NOTES

- Secrets required: private input `OS-nixCfg-secrets` + age key at `${HOME}/.ssh/agenix/id_ed25519`.
- CI uses Cachix (divitmittal) + Determinate magic-nix-cache.
- Top complexity hotspots: home/tty/find/yazi/{yazi.nix,keymap.nix}, macOS defaults, starship prompt.
