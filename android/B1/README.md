# B1 — Boox C69 HD (16 GB)

Controller-side Android management through nix-android, alongside M1 and E1.
This profile is on `feat/boox-c69`, based on `feat/nix-android-device` (PR #40).
The owner confirms the C69_M_STAR Android 11 firmware documented by the
community, for AI conversations, EPUBs, research papers and RSS. B1 is declared
as ARM64. The received reader matches the model, ABI, firmware fingerprint,
kernel and SDK in `identity.json`. The manifest sets a five-minute screen timeout
and the front-button mapping, manages the reading apps, and disables selected
packages.

## First connection

Requirements: this flake's Nix environment, a USB data cable, and USB debugging
authorized on the reader. Enable debugging through the device's app-management
or developer settings, depending on its firmware.

Run from this worktree's root:

```sh
nix develop
adb devices
bash android/B1/inspect.sh SERIAL
```

Use the reader's serial explicitly; M1 or E1 might also be connected. The script
reads selected properties, screen size and package inventories. Snapshots stay
outside Git in `${XDG_STATE_HOME:-$HOME/.local/state}/infra-nixCfg/B1/`, with
private file permissions. It does not install, disable, remove or reboot anything.
An interrupted snapshot is incomplete; rerun the command if it fails.

## Verify, plan and apply

Use the B1 controller from this repository root:

```sh
nix run .#b1-device -- --serial SERIAL inspect
nix run .#b1-device -- --serial SERIAL plan
# After reviewing the plan:
nix run .#b1-device -- --serial SERIAL apply
```

`inspect` only reads the selected reader. All modes verify the expected model,
SDK 30, ARM64 ABI, Bengal platform, exact firmware fingerprint and kernel prefix.
A mismatch stops before nix-android or a settings write. Inspect reports the
boot lock state and slot without assuming a missing slot means `_a`.
Use `--flake /path/to/this/checkout` if running outside the repository root.

The default settings retain **Back** on a short front-button press and use
**Recent Apps** on a long press, replacing the nonfunctional frontlight action
on this hardware. The screen sleeps after **five minutes** of inactivity.
Side buttons, display density, radio settings, Google services and keyboards
retain their existing configuration.

`plan` uses nix-android's read-only plan and preserves exit 3 for pending changes.
`apply` saves original values of every managed setting outside Git with private
permissions, runs nix-android, and sends `onyx.action.refresh_keymapping` only
when the switch succeeds. The reload runs even when the manifest already matches,
so retrying apply can recover from an interrupted reload. Prefer this wrapper to
calling `android-rebuild switch` directly, which does not send the Onyx reload.
These are reported community interfaces; read-back and physical button behavior
still need verification when B1 arrives.

Original values are in
`${XDG_STATE_HOME:-$HOME/.local/state}/infra-nixCfg/B1/before-apply-*/settings.json`.
Keep the **first** snapshot: later snapshots can contain already-managed values.
For recovery, restore the recorded namespace/key/value with Android `settings
put`; a recorded `"null"` represents an unset key and requires `settings delete`
instead. Reload the key mapping after restoring its settings. Reverting Git
alone does not restore Android state. Snapshots include the selected serial and
firmware identity and must remain outside the public repository.

## Recovery artifact and root research

`nix build .#b1-recovery --no-link --print-out-paths` obtains the TWRP image from
[Zeusx212 Power Studio v1.1.4](https://github.com/Zeusx212/onyx-c69hd-power-studio/releases/tag/v1.1.4),
verified against its pinned SHA-256 in `identity.json`. It only downloads an image;
it never reboots, unlocks, boots recovery or flashes a partition. The byte hash
identifies the upstream artifact, not a compatibility test on our unit.

The [recovery fork](https://github.com/Zeusx212/android_device_onyx_c69) reports
working e-ink/touch and root ADB, but still uses the stock prebuilt 4.19.157 kernel.
It provides a useful route to investigate our own partition backups after device
verification. It does not provide matching kernel source or a ReSukiSU/SUSFS
build. Do not substitute shared pre-patched boot images for our own stock images.
B1 booted the pinned TWRP image in RAM and we verified read access to both
slots' stock boot, vbmeta and recovery partitions. The backups stay outside
Git. Magisk 31.1 was patched on B1 from its own stock boot image, tested in RAM
and flashed to `boot_a`. TWRP was then flashed to `recovery_a`, booted from
that partition, and verified by readback. B1 retains stock recovery on slot B.
Before any recovery write, verify the serial, read
`is-userspace` and `current-slot` in Fastboot, and check the stock backups.
Use the explicit recovery partition for the selected slot. Restore that
slot's original recovery image to undo the change.

### Magisk modules

Declare module IDs, pinned archives, and the desired enabled state in
`magisk.nix`. Use a Nix-built ZIP or a hash-pinned download matching the ID
in `module.prop`. Grant **Shell** superuser access in Magisk for the CLI.

```sh
nix run .#b1-magisk -- --serial SERIAL plan
nix run .#b1-magisk -- --serial SERIAL apply
```

Planning is read-only and returns 3 when actions are pending. Apply stages
changed archives through Magisk and sets the enabled state. The controller
records each archive's SHA-256 in the module after a successful install, so
it can track provenance even when an upstream installer transforms the ZIP
contents. An existing UI install is adopted by reinstalling it once. Reboot
explicitly to activate changes. Removing an entry leaves it unmanaged. Set
`enable = false` and apply to disable it.

The `b1-media` output builds the first managed module, which supplies
standby and shutdown art and an uncompressed boot animation. Edit
`media/build.py` to customize the artwork. To use the 758 × 1024 image
without the overlay, copy `B1-standby.png` from the same output into
`/sdcard/Pictures/Screensaver/` and select it in BOOX's screensaver settings.

The front-button mapping follows
[Zeusx212's native Onyx setting interface](https://github.com/Zeusx212/onyx-c69hd-button-remap).
The broad RAM/debloat presets, root wake daemon, and GUI flashing fallbacks are
not dependencies of this profile. No external desktop utility is executed.

### Keyboard

[Unexpected Keyboard](https://github.com/Julow/Unexpected-Keyboard)
(`juloo.keyboard2`, declared in `apps.nix`) replaces Onyx's bundled LatinIME.
`keyboard/layout.xml` is the [TLTR](https://github.com/DivitMittal/TLTR) QWERTY
layout, deployed and made the default IME declaratively. Grant **Shell**
superuser access in Magisk for the CLI.

```sh
nix run .#b1-keyboard -- --serial SERIAL plan
nix run .#b1-keyboard -- --serial SERIAL apply
```

Unexpected Keyboard has no file-watching custom-layout mechanism; its layout
is one JSON-encoded string in its own SharedPreferences file
(`/data/data/juloo.keyboard2/shared_prefs/juloo.keyboard2_preferences.xml`,
key `layouts`). `apply` writes that file directly as root, restores its
owner/SELinux context, force-stops the app so it reloads, then enables and
sets Unexpected Keyboard as the default IME, retrying `ime set` a few times
to ride out `InputMethodManagerService`'s enabled-method cache catching up
with a just-issued `ime enable`. `plan` only reads state back.

`keyboard/layout.xml` is a close relative of
`hosts/droid/M1/keyboard/layout.xml` (Termux Launcher's embedded keyboard on
M1), not the same file: the M1 variant's space-key diagonal swipes call
Termux Launcher's own window/session-switching commands (`tool:...`), which
the standalone Unexpected Keyboard app would type as literal text instead of
running. This copy drops those five swipes and keeps everything else
identical. Update both files together when the shared TLTR design changes.

## Select debloat entries

The reference is [RodrickRK/boox-debloat](https://github.com/RodrickRK/boox-debloat),
specifically `apps.json` at revision
`e045a46d0d694f94814838aac1a33b7e601e7382`. It targets **C69_M_STAR education
firmware**, not every C69 HD. `catalog.nix` records its candidates and protected
packages. The B1 manifest selects printing, print recommendations, the Android
Easter egg, the education app, Onyx Mail, NFC and the two Onyx diagnostic apps.

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
nix run .#b1-device -- --serial SERIAL plan
# After reviewing the exact changes:
nix run .#b1-device -- --serial SERIAL apply
nix run .#b1-device -- --serial SERIAL plan
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
nix run .#b1-device -- --serial SERIAL plan
```

Removing the declaration or reverting Git does **not** undo a disable. Android
convergence is not an atomic NixOS rollback. The inventory snapshot records which
packages were already disabled, so only undo changes made during this setup.
This profile does not uninstall system apps; restoring apps removed by other
tools requires a separate, firmware-compatible procedure.

## Reading apps and library

The `apps.nix` module pins KOReader, inkOS, Aurora Store and Obtainium from
their upstream releases and EinkBro and Feeder from F-Droid.

| Use                               | App      | Workflow                                                              |
| --------------------------------- | -------- | --------------------------------------------------------------------- |
| EPUBs                             | KOReader | Local books; OPDS for a hosted library later                          |
| Research papers                   | KOReader | PDF margin crop, zoom or reflow; retain the original PDF              |
| AI conversations and web articles | EinkBro  | Bookmark the preferred hosted AI service; test login and rendering    |
| Android home screen               | inkOS    | Choose inkOS as the default Home app on B1 if desired                 |
| RSS                               | Feeder   | Offline articles and OPML subscriptions; independent local feed state |

ChatGPT is an attended package. On a fresh B1, verify the device with
`b1-device inspect` and review the plan before installing the pinned APKs.

```sh
nix run .#android-rebuild -- bootstrap --flake .#B1 --serial SERIAL
```

Bootstrap pauses while ChatGPT is missing. Install OpenAI's ChatGPT through
Aurora Store, then rerun the B1 plan and apply.

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

The device imports `apps.nix` and resolves APKs from `apps.lock.json`. KOReader uses
`org.koreader.launcher`: the F-Droid flavor (`org.koreader.launcher.fdroid`)
disables user patches. See [the KOReader setup](koreader/README.md) for the
pinned plugins, Lua profiles and their deployment:

```sh
nix run .#android-rebuild -- update --flake .#B1 --lock android/B1/apps.lock.json
git diff -- android/B1/device.nix android/B1/apps.lock.json
nix run .#b1-device -- --serial SERIAL plan
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
feed import remains manual; KOReader preferences are managed by its separate bundle.

## KOReader customizations

See [koreader/README.md](koreader/README.md) for the managed Lua configuration,
KOAssistant research prompts, Markdown export, reading profiles and deployment.
