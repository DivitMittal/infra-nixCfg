# Legacy Raycast CLI builds on T2

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
Other API versions and platforms receive no derivation override. The existing
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
