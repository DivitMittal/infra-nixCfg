# B1 KOReader: reading, research and AI

This bundle is tailored to Android 11 on the C69 HD: EPUBs, research PDFs,
selected-passage AI conversations and occasional RSS-to-EPUB downloads. It has
been built and tested on the controller; it has not run on the physical reader.

## What is managed

| Component       | Configuration                                                                           |
| --------------- | --------------------------------------------------------------------------------------- |
| KOReader        | Official GitHub Android release `v2026.07.1`, package `org.koreader.launcher`           |
| KOAssistant     | Release `v0.24.1`, archive SHA-256 pinned in `sources.json`                             |
| EPUB defaults   | Font size 24, 110% line spacing, modest margins                                         |
| PDF defaults    | Automatic margin crop, paged movement, original layout                                  |
| Profiles        | `B1 EPUB`, `B1 Paper original`, `B1 Paper reflow`                                       |
| Highlights      | Built-in exporter enabled for Markdown, backlinks, `koreader/exports/`                  |
| Vocabulary      | Dictionary lookups recorded with context for later review                               |
| RSS             | Built-in News downloader enabled; three KOReader release items as a small starting feed |
| Other built-ins | Profiles, gestures, OPDS and reading statistics enabled                                 |

KOReader's Android F-Droid flavor disables user patches. The optional B1 app
bundle therefore declares the official GitHub APK instead. See
[KOReader's user-patch documentation](https://github.com/koreader/koreader/wiki/User-patches).
If migrating from F-Droid, preserve its reader data, books and annotations first;
the official app is a different Android package. This deployment does not
uninstall either app. Launch the official app, grant storage access and confirm
that it sees the intended library before proceeding.

`payload/settings/b1.lua` owns the listed defaults and named profiles. The
priority-2 startup patch reapplies those keys on each launch, preserving unrelated
global settings, other profiles and per-book state. Change managed defaults in
the repository. Existing per-book choices still override global defaults.
The named profiles are manual choices, not automatic format detection. Choose
one in the Profiles menu; the two PDF profiles let you compare original layout
against reflow without making reflow the default for equations or figures.

## AI actions

Select text, open KOAssistant's action menu, then choose:

- **Explain this passage:** central idea, reasoning, terminology and an example.
- **Critique the evidence:** claims, methods, assumptions, limitations and tests.
- **Unpack the equation:** symbols, steps, intuition and dimensional checks.
- **Make recall questions:** five questions followed by a separate answer key.
- **Discuss without spoilers:** interpretations and a focused discussion question.

The prompts ask for grounded answers and explicitly acknowledge missing context.
They send the selected passage and book metadata when invoked; no provider calls
are made by building or deploying this bundle. Whole-book extraction and library
scanning default to off. Responses use Markdown at size 22, without streaming or
automatic scroll, to reduce repeated e-ink refreshes. Plugin auto-update checks
are off so code changes go through the pinned bundle.

In **Tools → KOAssistant → Settings**, choose a provider/model and enter its
credentials on the device. UI choices override `configuration.lua` defaults.
The plugin stores its settings in `settings/koassistant_settings.lua`, which
this deployment never replaces. A browser login alone does not configure the
plugin's provider. Do not put credentials in this repository or the Nix bundle.
The exported Markdown and AI notes are reading data; they are not automatically
committed, synced or sent to an external notes service.

## Build, review and deploy

First verify B1 with `b1-device inspect`, enable `./apps.nix` in `android/B1/device.nix`, resolve
`android/B1/apps.lock.json`, review the nix-android plan and install the apps as
described in the parent README. The APK declaration pins the KOReader release;
the lock records the selected APK's hash and signer. The configuration bundle
itself is independent of the reader's ABI.

Run from the `feat/boox-c69` worktree root:

```sh
nix build .#b1-koreader --no-link --print-out-paths
nix build .#checks.x86_64-darwin.b1-koreader --no-link
python3 android/B1/koreader/deploy.py --serial SERIAL
# After reviewing the reader, data path and managed files:
python3 android/B1/koreader/deploy.py --serial SERIAL --apply
```

Use your controller's system in the check attribute if it differs from L1's
`x86_64-darwin`. New files must be tracked by Git for Git-backed flake references.
`--bundle /nix/store/...-b1-koreader-...` reuses an already-built bundle.

Exit KOReader from its menu before deployment. The script requires the official
app, a stopped process, and an initialized `/sdcard/koreader/settings.reader.lua`.
It refuses to force-stop a running reader. The default invocation only reviews.
`--data-dir /storage/emulated/0/koreader` supports the equivalent primary-storage
path if that is how the reader exposes it.

Deployment uploads to a staging folder and checks every payload checksum before
replacing five managed paths. Existing versions, `settings.reader.lua` and
`settings/profiles.lua` are backed up under `koreader/.b1-backups/<timestamp>/` on
the reader. The plugin directory is replaced as a unit to avoid stale code;
other plugins, books, sidecars, history, highlights and API settings remain
outside the managed paths. Repeating deployment restores the repository's
managed files, with another backup. Retain those backups until verified.

Replacement failure attempts to restore managed paths while ADB remains
reachable. A disconnected device can require manual recovery. This is not an
atomic device-wide rollback, and backups on shared storage are not encrypted.

## Daily workflow and recovery

EPUBs use `B1 EPUB`. For papers start with `B1 Paper original`, try landscape or
zoom/crop in KOReader, then compare `B1 Paper reflow` if text remains too small.
Check the original PDF for mathematical notation that extracted text mangles.
Dictionary lookups populate Vocabulary builder. Export highlights through the
Export highlights menu; retrieve `koreader/exports/` with USB or ADB when needed.
PDF annotation embedding is left to an explicit per-document choice.

Feeder remains the everyday feed inbox. For articles you want as a reading
document, edit `payload/news/feed_config.lua`, deploy, then explicitly run News
downloader. Add full T3 RSSHub route URLs, not `http://T3.lan:31200` alone.
There are no scheduled downloads. OPDS is enabled for a future Calibre catalog;
this change does not invent or expose an OPDS server.

If startup misbehaves, exit the app and move
`patches/2-b1-reading.lua` out of `patches/` to stop applying the custom defaults.
That does not undo previously saved settings. To undo them, restore
`settings.reader.lua` and `settings/profiles.lua` from the chosen device backup
while the app is closed; remove a newly created managed profile if no original
profiles file existed. Restore the backed-up plugin directory to undo a plugin
update. Avoid restoring old global settings after substantial new reading
activity unless you intend to revert those later settings changes too.

The remaining acceptance checks on B1 are font size/contrast, crop/reflow on real
papers, dictionary lookup, highlight export, profile switching, a small news
download, and one provider request. Fonts, networking, PDF rendering and plugin
UI compatibility still need this physical-device check.
