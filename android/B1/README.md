# B1 — Boox C69 HD (16 GB)

Controller-side Android management through nix-android, alongside M1 and E1.
This profile is on `feat/boox-c69`, based on `feat/nix-android-device` (PR #40).
The owner reports Android 11 (SDK 30), for AI conversations, EPUBs, research
papers and RSS. The device has not been inspected or changed. Its exact firmware,
ABI and display size remain unknown; the initial manifest has no actions.

## First connection

Requirements: this flake's Nix environment, a USB data cable, and USB debugging
authorized on the reader. Enable debugging through the device's app-management
or developer settings, depending on its firmware.

Run from this worktree's root:

```sh
nix develop path:.
adb devices
bash android/B1/inspect.sh SERIAL
```

Use the reader's serial explicitly; M1 or E1 might also be connected. The script
reads selected properties, screen size and package inventories. Snapshots stay
outside Git in `${XDG_STATE_HOME:-$HOME/.local/state}/infra-nixCfg/B1/`, with
private file permissions. It does not install, disable, remove or reboot anything.
An interrupted snapshot is incomplete; rerun the command if it fails.

Compare `ro.product.model`, the build fingerprint, SDK and package inventory
before treating this as the firmware targeted by the upstream tool. Replace
the provisional `device.abi = "armeabi-v7a"` with the reported
`ro.product.cpu.abi`, and change `abi` in `apps.lock.json` to match. Supported
values in the pinned nix-android are `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
The engine refuses an ABI mismatch, but it does not verify model or firmware:
serial selection and the inventory review are essential.

The commands use `path:.` so Nix includes the new, untracked profile files
during review. Once the files are tracked by Git, ordinary `.#B1` references
work too.

## Establish the baseline

```sh
nix run path:.#android-rebuild -- build --flake path:.#B1
nix run path:.#android-rebuild -- plan --flake path:.#B1 --serial SERIAL
```

The baseline should report no pending actions. A plan exits 3 when changes are
pending; inspect its output. Stop if package queries fail on this firmware.
Upstream primarily tests recent Pixel/GrapheneOS devices, so a successful Nix
evaluation alone does not prove this reader supports every Android primitive.
Do not use snapshot/import as the first probe: older Android lacks `cmd role`.

## Select debloat entries

The reference is [RodrickRK/boox-debloat](https://github.com/RodrickRK/boox-debloat),
specifically `apps.json` at revision
`e045a46d0d694f94814838aac1a33b7e601e7382`. It targets **C69_M_STAR education
firmware**, not every C69 HD. `catalog.nix` records its candidates and protected
packages. No candidate is selected by default.

After checking the package is present and unnecessary on this device, start with
one entry in `device.nix`, for example:

```nix
boox.disabledPackages = ["com.android.egg"];
```

This profile uses `pm disable-user --user 0` rather than the upstream tool's
user-level uninstall. It retains APKs and app data. The module restricts both
`boox.disabledPackages` and direct `android.packages.disabled` declarations to
the candidate catalog. It excludes the Onyx launcher, ksync, screen manager,
gallery, media providers, OTA and Google components. It does not repair any
of these if a previous tool already removed or disabled them.

```sh
nix run path:.#android-rebuild -- plan --flake path:.#B1 --serial SERIAL
# After reviewing the exact changes:
nix run path:.#android-rebuild -- switch --flake path:.#B1 --serial SERIAL
nix run path:.#android-rebuild -- plan --flake path:.#B1 --serial SERIAL
```

Check reading, sleep/wake, setting a sleep picture, Wi-Fi and USB after each
small batch and after a reboot. Missing candidates are skipped by the engine;
that does not establish firmware compatibility. Keep `apps.cleanup = "none"`:
an incomplete manifest must not uninstall existing third-party apps.

## Restore a disabled package

Remove the package from `boox.disabledPackages` first, then explicitly enable it:

```sh
adb -s SERIAL shell pm enable --user 0 com.android.egg
adb -s SERIAL shell pm list packages -e
nix run path:.#android-rebuild -- plan --flake path:.#B1 --serial SERIAL
```

Removing the declaration or reverting Git does **not** undo a disable. Android
convergence is not an atomic NixOS rollback. The inventory snapshot records which
packages were already disabled, so only undo changes made during this setup.
This profile does not uninstall system apps; restoring apps removed by other
tools requires a separate, firmware-compatible procedure.

## Reading apps and library

The optional `apps.nix` bundle declares KOReader from its official GitHub release and EinkBro/Feeder from F-Droid:

| Use                               | App      | Workflow                                                              |
| --------------------------------- | -------- | --------------------------------------------------------------------- |
| EPUBs                             | KOReader | Local books; OPDS for a hosted library later                          |
| Research papers                   | KOReader | PDF margin crop, zoom or reflow; retain the original PDF              |
| AI conversations and web articles | EinkBro  | Bookmark the preferred hosted AI service; test login and rendering    |
| RSS                               | Feeder   | Offline articles and OPML subscriptions; independent local feed state |

[KOReader](https://github.com/koreader/koreader) supports EPUB/PDF and e-ink
reading. [EinkBro](https://github.com/plateaukao/einkbro) avoids unnecessary UI
animations; its current source requires SDK 24. [Feeder](https://github.com/spacecowboy/Feeder)
requires SDK 29 in current source, within Android 11's SDK 30, and supports
offline reading and OPML import/export. It does not synchronize read state with
an RSS server. For an existing server, first try its web UI in EinkBro, then
choose a compatible native client if needed.

This repository already declares RSSHub on T3 at `http://T3.lan:31200`
(`hosts/nixos/T3/rsshub.nix`). Add the desired RSSHub route URLs as Feeder
subscriptions while on the home LAN; the base URL alone is not a feed. RSSHub
generates feeds and Feeder holds subscriptions/read state. Check that the
service is deployed and reachable before adding it. Desktop Calibre is also
configured in `home/gui/docs.nix`; use it as the main EPUB library. No Calibre
OPDS server is declared by this change.

After confirming ABI, uncomment `./apps.nix` in `device.nix` and resolve pins.
The bundle is disabled initially and its APKs are not locked yet. KOReader uses
`org.koreader.launcher`: the F-Droid flavor (`org.koreader.launcher.fdroid`)
disables user patches. See [the KOReader setup](koreader/README.md) for the
pinned plugins, Lua profiles and their deployment:

```sh
nix run path:.#android-rebuild -- update --flake path:.#B1 --lock android/B1/apps.lock.json
git diff -- android/B1/device.nix android/B1/apps.lock.json
nix run path:.#android-rebuild -- plan --flake path:.#B1 --serial SERIAL
```

The explicit `--lock` matters in this multi-device repository. Review SDK
compatibility separately: the lock resolver's ABI selection is not a substitute
for inspecting the chosen APK's minimum SDK. App pins are minimum versions;
nix-android does not downgrade newer installed versions.

For the first books, use USB file transfer or an explicit `adb -s SERIAL push`
to a chosen reader folder. Keep the main library on the computer; the 16 GB
listing is storage, not a reason to assume RAM or install a large background
sync stack. Add sync after confirming the workflow and battery behavior.

Keep firmware-specific e-ink refresh settings, sleep timing and front-light
controls in the Boox UI until their supported interfaces are verified. Preserve
the stock launcher and sleep-screen components. This setup does not install
nix-on-droid or Termux Launcher: whether those fit depends on the actual ABI,
Android version and intended use.

For AI, start with browser login to the preferred hosted service. Test typing,
scrolling and long replies on the reader before choosing a native client. The
manifest manages app installation, not browser sessions or service credentials.
Keep API keys and login data outside Git. Maintain the Android WebView through
the device's supported updater; a modern browser app still depends on its web
engine. Hosted AI chat performance on this exact firmware is unverified.

Start with a light theme, large text, paged movement and reduced animation in
each app where available. Try PDF cropping/landscape for papers; a small screen
can still make two-column papers awkward. Export feed subscriptions as OPML and
keep the non-secret subscription list with the configuration once selected;
the current profile does not import feeds or manage app-internal preferences.

## KOReader customizations

See [koreader/README.md](koreader/README.md) for the managed Lua configuration,
KOAssistant research prompts, Markdown export, reading profiles and deployment.
