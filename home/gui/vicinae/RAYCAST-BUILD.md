# Raycast extension builds on T2

`setup.nix` retains all 23 selected extensions and uses the pinned Vicinae
`nix/mkRayCastExtension.nix` helper. That helper uses `buildNpmPackage` with
`importNpmLock`, runs the extension's existing npm build script, and installs
`$HOME/.config/raycast/extensions/*`. It does not supply a Linux CLI.

Four selected extensions lock older `@raycast/api` releases whose `bin/ray`
is a shell downloader rather than a bundled CLI:

| Extension                | Locked API / CLI version |
| ------------------------ | ------------------------ |
| guitar-chords            | 1.39.0                   |
| onenote                  | 1.46.0                   |
| glyph-search             | 1.47.3                   |
| restart-system-processes | 1.80.0                   |

The downloader requests `https://raycast.com/get-cli/`, which fetches
`https://cli.raycast.com/${VERSION}/linux/ray`. Adding curl to the sandbox
would still leave an undeclared network dependency. Instead, `setup.nix`
fetches each versioned CLI through `fetchurl` with a SHA-256 content hash.
These upstream Linux CLIs are static x86_64 Go executables.

On x86_64 Linux, `preBuild` replaces the downloader with the fetched executable
and verifies `ray version` against the extension lockfile before the npm build.
Replacing the downloader also avoids API 1.39.0's stray `file /usr/local`
command. Original build scripts, including `ray build -e dist`, remain intact.
Other API versions and platforms receive no legacy CLI override. The existing
telemetry/update environment settings remain in place. This patch does not
add support for executing these legacy x86_64 binaries on Linux ARM.

## Validation on T2

Validated on 2026-11-19 using the deployment source's nixpkgs and pinned Vicinae
source, importing only this module to obtain individual extension derivations.
No full Home Manager evaluation, activation, or deployment was performed.

All four extension builds completed successfully under the Nix sandbox with
`--max-jobs 1 --cores 2`. Transient service `raycast-check-fixed` exited 0;
its full build log is `/var/log/raycast-check-fixed.log`. Final formatted source
was checked again by `raycast-check-final`, which exited 0 and reused the same
successful outputs; log: `/var/log/raycast-check-final.log`.

| Extension                | Successful output in `/nix/store/`                          |
| ------------------------ | ----------------------------------------------------------- |
| onenote                  | `0hxranzsk07r3569fqzsiiyj9p9zg1hq-onenote`                  |
| guitar-chords            | `g524j71rxylz0wyvnib7qn0mpx7my7gd-guitar-chords`            |
| glyph-search             | `a8gsw8p56bf3idnmnj1q36p6ba3913jm-glyph-search`             |
| restart-system-processes | `50c92myiwrpcqkxhfb4r7dm7sgncp2fl-restart-system-processes` |

A narrow before/after derivation comparison confirmed all 23 selections remain
and the other 19 extensions have identical `drvPath` values.

Installed manifests retain the source command names: OneNote `index`, guitar
`chords-quickfind` and `chords-search`, glyph search `index`, and restart `index`.
Each command has its corresponding installed JavaScript bundle. GUI interaction
was not tested. `nix fmt home/gui/vicinae/setup.nix` passed.

The initial diagnostic run (`/var/log/raycast-check-four.log`) failed the version
assertion because it invoked the old guitar wrapper; the final patch replaces
that wrapper directly. The successful logs above supersede that attempt.

The deployment owner should integrate these files, run the whole-configuration
CI evaluation under `.apm/instructions/ci-eval.instructions.md`, and resume the
T2 full Home Manager build alongside the independently handled REAPER fix.

## Stock-tracker Electron download

The subsequent full-profile build failed in stock-tracker's dependency rebuild:
`electron/install.js` tried to download from GitHub inside the sandbox. The
locked dependency chain is stock-tracker → `react-devtools` 6.1.1 (development
dependency) → Electron 23.3.13. Electron's installer explicitly exits successfully
when `ELECTRON_SKIP_BINARY_DOWNLOAD` is set.

Stock-tracker's locked `@raycast/api` 1.104.15 uses the Node `bin/run.js` CLI with
esbuild. Its build command does not import Electron; none of stock-tracker's
command sources import Electron or react-devtools. The standalone React DevTools
developer UI brings Electron, but the extension's production build does not need
that executable. No alternate CLI or binary fetch is required.

`setup.nix` sets `ELECTRON_SKIP_BINARY_DOWNLOAD=1` only for stock-tracker. All npm
packages, the SDK, and both commands remain present; lifecycle scripts still run.
The standalone Electron DevTools executable is not provisioned by this package.

### Stock-tracker validation on T2

On 2026-11-19, built only stock-tracker using the current deployment source's
nixpkgs and pinned Vicinae helper, with `--max-jobs 1 --cores 2`. The direct SSH
build exited 0; no service was created or changed. Complete log:
`/var/log/raycast-check-stock.log`.

The build passed dependency rebuild, the original `ray build -e dist`, compilation
of both `src/index.tsx` and `src/menubar.tsx`, TypeScript checking, and installation.
Successful output:
`/nix/store/ikq4mncbp4iccb0pbn0rxsvjkqav9rjf-stock-tracker`.

Installed manifest commands and SDK dependencies are identical to the pinned
source. Both `index.js` (View Stocks) and `menubar.js` (Menu Bar Stocks) exist and
contain no `require("electron")` or `require("react-devtools")` calls. GUI behavior
and live Yahoo Finance data were not exercised.

A narrow derivation comparison against the full-profile source
`/nix/store/qgky2i9n53hmfhwsc5ilqpsp6c7p4pf1-source` confirmed that stock-tracker is
the only changed extension derivation; the other 22 are identical, including the
four previously fixed legacy builds. All 23 selections remain. The parent should
integrate the stock-specific environment setting and resume its full-profile
validation; no full-profile build or deployment was run for this change.
