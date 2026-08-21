---
description: hosts/darwin/ knowledge — macOS host configs, defaults, programs, services for L1
applyTo: "hosts/darwin/**"
---

# AGENTS (hosts/darwin/)

## OVERVIEW

macOS host configs via mkCfg class="darwin"; L1 host layering over common + darwin common.

## STRUCTURE

```
hosts/darwin/
├── default.nix      # registers darwin hosts (L1) using mkCfg
└── L1/
    ├── defaults/    # defaultsPrefs.nix, manual_setup.kdl
    ├── programs/    # app modules (bak/, cli utils)
    ├── services/    # launchd services (e.g., kanata-tray)
    └── home/        # host+user overrides (if present)
```

## WHERE TO LOOK

| Task           | Location                      | Notes                                                               |
| -------------- | ----------------------------- | ------------------------------------------------------------------- |
| Host entry     | default.nix                   | mkCfg {class="darwin"; hostName="L1"} with overlays/secrets         |
| macOS defaults | L1/defaults/defaultsPrefs.nix | 190+ lines; Dock/Finder/Trackpad/Screenshot; DO NOT thumbnails note |
| Manual steps   | L1/defaults/manual_setup.kdl  | Post-install checklist (e.g., low-power-mode "never")               |
| Apps/programs  | L1/programs/                  | App bundles, CLI tools; bak/ stores backups                         |
| Services       | L1/services/                  | launchd daemon configs (e.g., kanata-tray)                          |

## CONVENTIONS

- Uses `lib.custom.scanPaths` inside host dir for auto-imports.
- Layer order: common/all → common/hosts/all → common/hosts/darwin → hosts/darwin/L1 → hosts/darwin/L1/home (if any).
- macOS packages may come from overlays/customDarwin or brew/mac-app-util (see overlays/custom.nix + flake inputs).

## ANTI-PATTERNS

- Defaults files: respect inline comments (e.g., DO NOT flash date separators, screenshot thumbnail off).
- Do not bypass mkCfg; keep host registration through default.nix for overlays/secrets wiring.

## NOTES

- deploy-rs not used here (Android only); builds via `hts -v --show-trace`.
- allowUnsupportedSystem=false inherited; requires access to infra-nixCfg-secrets for hostSpec.
- Path filters in CI: darwin workflow ignores nixos/droid/home-only changes.
