# On-demand command launchers

`home/media/books.nix` installs a small `zlib` launcher, not the application.
The launcher runs the pinned `zlib-cli` package from the configuration's source
snapshot with `nix run`. It works before the configuration is pushed and does
not depend on the current directory. Arguments and exit status are preserved.

To add another infrequently used command:

```nix
home.packages = [
  (lib.custom.mkNixRunBin pkgs "hello" "nixpkgs#hello")
];
```

Use a pinned flake reference or `${self.outPath}#package-name` for reproducible
versions. Keep the target as an installable string, not an interpolated package
derivation, to avoid retaining its closure in the Home Manager generation.
Nix must be on PATH at runtime. The first invocation may need network access.
`nix run` still downloads/builds into `/nix/store`, but the application is not
installed or rooted by the home profile and can be garbage-collected when no
other roots retain it. This is deferred installation, not store-free execution.

## Candidates already in this repo

| Tool                     | Current declaration         | Suggested approach                                                                                                                                              |
| ------------------------ | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `yt-dlp`                 | `home/media/video.nix`      | Best rolling candidate: `uvx --refresh yt-dlp` for upstream stable, or opt into `--prerelease allow` for nightly. Keep `ffmpeg` available on PATH.              |
| `oci`, `ovhcloud`        | `home/dev/cloud.nix`        | If used occasionally, try `uvx --from oci-cli oci` and pinned `nix run` for the OVH CLI. Preserve `OCI_CLI_CONFIG_FILE` and pin cloud tooling for scripted use. |
| `pandoc`                 | `home/tty/viewers.nix`      | Pinned `nix run` for occasional document conversions. Keep eager if editors or offline scripts call it regularly.                                               |
| Czkawka                  | `home/tools/cleanup.nix`    | A pinned `nix run` launcher for whichever CLI or GUI binary you actually use. Likewise consider `kondo` if it's an occasional cleanup command.                  |
| `speedtest-go`, `iperf3` | `home/tty/network/misc.nix` | Pinned `nix run` if used only for benchmarks. Keep diagnostic tools eager if you need them to troubleshoot a broken connection.                                 |

`wrangler` and `dl-librescore` already use `pnpm dlx ...@latest`, so switching
those to `bunx` only makes sense if you want to standardize runners and have
verified the cold-cache launch. `markitdown`, `visidata`, and several PDF tools
already use the `uvx` pattern. Keep services, activation dependencies, and
commands used by key bindings or unattended scripts pinned and available
without a first-run download.

## Darwin and zerobrew

Existing `lib.custom.mkZbxBin "formula"` launchers run through the managed
zerobrew package and keep application files outside the Nix store. Use this for
supported formulas whose executable has the same name as the formula.

Do not use `mkZbxBin "zlib"`: Homebrew's core `zlib` is the compression library,
not heartleo's CLI. The upstream CLI formula is `heartleo/tap/zlib-cli`, while
its executable is `zlib`. Zerobrew 0.4.2's `run` implementation unconditionally
looks for `bin/<formula-token>` and has no executable override, so
`zbx heartleo/tap/zlib-cli` cannot launch it. The pinned CLI therefore uses the
working `nix run` backend on Darwin too. Revisit this once zerobrew supports
choosing the executable, as well as installing this third-party source formula.

Upstream references:

- https://github.com/heartleo/zlib
- https://github.com/heartleo/homebrew-tap/blob/main/zlib-cli.rb
- https://github.com/zerobrewhq/zerobrew/blob/v0.4.2/zb_cli/src/commands/run.rs
