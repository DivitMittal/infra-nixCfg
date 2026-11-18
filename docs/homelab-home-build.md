# Homelab Home Manager dependency fetch fix

The complete T2 desktop and AI profile failed at
`/nix/store/37z0sbnsi9r1igmi4vgwsb3nw6xlganm-aicommit2-pnpm-deps.drv`.
This investigation made no changes and started no builds on T2.

## Evidence and diagnosis

- Owner: `ai-nixCfg` at `013bad150b9ab59b1c7af7d00e009f1aa7a04a49`,
  `config/home/cli/vcs.nix`, installs its `aicommit2` input's flake package
  directly. An overlay of `pkgs.aicommit2` would not affect it.
- That input is `tak-bro/aicommit2` at
  `ecd326951ddf05b235150d097bb83ff7297070b3`, version `v2.16.0`.
  Its source on T2 is
  `/nix/store/canx4iq89k3zl6n3gfwsrlhf78gm659k-source`.
- The dependency derivation uses pnpm 11.9.0, fetcherVersion 3, and
  `--force --ignore-scripts --frozen-lockfile`. Fetching all architectures
  is intentional for this fixed-output dependency store. Copilot SDK is
  an explicit optional dependency; removing it would remove functionality.
- Logs show repeated `GET ... error (23)` during partial 129–147 MB Copilot
  downloads, followed by a missing darwin-arm64 `package.json`. The log
  does **not** identify curl. The installed pnpm bundle uses Undici fetch
  with `AbortSignal.timeout(timeout)` and a 60,000 ms default. Its retry
  formatter prints `error.code`, including numeric DOMException codes.
  A read-only invocation of the exact Node 24.16 binary on T2 reproduced
  `{ "name": "TimeoutError", "code": 23 }` with `AbortSignal.timeout(1)`.
  These observations strongly support a response deadline failure rather
  than curl write error 23. They do not independently reproduce the entire
  failing install.
- Registry inspection from the Mac streamed the darwin-arm64 archive and
  found `package/package.json` identifying the expected package at 1.0.71.
  The archive is 130,336,069 bytes. The manifest is present upstream;
  the later ENOENT is consistent with an interrupted optional dependency
  fetch. This was an archive read, not a package build or install.
- T2 reported 139 GiB available on the filesystem holding `/nix` and `/tmp`.

## Patch and parent wiring

`home/_homelab-package-fixes.nix` raises only this package's dependency-fetch
timeout to ten minutes and limits network concurrency to four. It preserves
the existing dependency hash, source, lockfile, pnpm version, build hook,
Copilot SDK, and all other Home Manager packages. The existing hash remains
an integrity check; a build must confirm that the fetched store matches it.

The module is explicitly imported by the additional modules for T2 and T3 in
`home/default.nix`. The internal guard also
limits it to those two host names on x86_64-linux. This replaces only the
upstream VCS module's package contribution, mapping aicommit2 to its overridden
derivation while retaining the upstream package list, including geminicommit.
Do not add this module to an auto-imported directory or change the lockfile.

## Validation and remaining deployment check

Completed locally without builds:

- Alejandra formatting, `nix-instantiate --parse`, and `git diff --check` pass.
- A narrow evaluation of the locked aicommit2 package confirms the two
  environment exports, changed package and dependency `drvPath`, unchanged
  `src`, unchanged `outputHash`, and retention of geminicommit.
- A small `lib.evalModules` harness importing both the locked VCS module
  and this replacement returns exactly two packages for each of T2, T3,
  and L2. T2/T3 select the changed aicommit2 derivation; L2 selects the
  original. All three retain the original dependency hash. This checks
  module disabling/merging without evaluating a Home Manager profile.
- Evaluation emits existing upstream deprecation warnings for
  `pnpm.configHook` and `pnpm.fetchDeps`.

The patch requires no package removal, service changes, or live profile
changes. Validate formatting and small package attributes locally; perform
full Home Manager evaluation on native GitHub CI as required by
`.apm/instructions/ci-eval.instructions.md`.

After wiring, the parent should verify in CI that the T2 activation package
evaluates and selects an aicommit2 dependency derivation whose `preInstall`
exports the two settings above, with the original `outputHash` intact. Then
the parent can perform the authorized deployment build on T2, after accounting
for its existing live `--keep-going` build. This investigation did not run it.
Success requires the dependency store hash check, aicommit2 build, and complete
T2 activation build to pass; evaluation alone cannot establish those results.
If the dependency hash differs, inspect the actual store-format difference
before changing it. Do not guess a new hash or disable optional dependencies.

## Follow-up: successful download, incompatible store hash

The deployment build of
`/nix/store/3y6ly56cagcixp2s69c24iy5gc1z87mf-aicommit2-pnpm-deps.drv`
completed fetching and fixup, then reported:

```text
specified: sha256-oemBe947Rq6toX7t+ukWzohwqBzbYqHlSSet3yoGBmY=
got:       sha256-BKrEDtmqd1Xtt9lEaAZ679GIca09gjLgjFflT09x8rM=
```

Read-only inspection of `/var/log/agent-dependency.log` confirmed effective
`fetchTimeout: 600000`, `networkConcurrency: 4`, and frozen-lockfile resolution.
The retained result was registered at
`/nix/store/hnndm5zjj4jzl4pihn60kj082lafdvqf-aicommit2-pnpm-deps` with the
reported actual NAR hash. Its `pnpm-store.tar.zst` is 1,113,744,624 bytes and
contains `v11/files/...` and `v11/index.db`.

The SQLite index was streamed to the Mac and inspected entirely in memory:
its 1,042 package-integrity keys exactly match the 1,042 unique archive
integrities in the pinned source's `pnpm-lock.yaml`, with no missing or extra
integrities. It includes Copilot SDK 1.0.7, Copilot 1.0.71, and all eight
Copilot architecture packages at 1.0.71, including darwin-arm64. The SQLite
header's WAL-mode flags were adjusted only in the transient in-memory copy
to allow SQLite deserialization; no target or local database file was written.
This comparison checks the index against the lock; it does not independently
rehash every stored package file or substitute for the final Nix hash check.

There are two distinct integrity layers: the lock pins each downloaded archive,
while the dependency derivation's NAR hash pins the resulting normalized store
representation. Matching archive-integrity keys do not imply that different
pnpm store formats or fetcher representations have the same NAR hash.

### Verified builder differences

The aicommit2 source's **own** `flake.lock` pins nixpkgs
`7fd36ee82c0275fb545775cc5e4d30542899511d`
(`sha256-9h7+4/53cSfQ/uA3pSvCaBepmZaz/dLlLVJnbQ+SJjk=`).
That revision supplies pnpm **10.13.1**, whose npm archive is pinned to
`sha256-D57UjYCJlq4AeDX7XEZBz5owDe8u3cnpV9m75HaMXyg=`.
Its fetcher writes the pnpm store directly to `$out`, normalizes JSON and
permissions there, and does not produce a compressed store archive.
See the pinned [pnpm version definitions](https://github.com/NixOS/nixpkgs/blob/7fd36ee82c0275fb545775cc5e4d30542899511d/pkgs/development/tools/pnpm/default.nix)
and [fetcher recipe](https://github.com/NixOS/nixpkgs/blob/7fd36ee82c0275fb545775cc5e4d30542899511d/pkgs/development/tools/pnpm/fetch-deps/default.nix).

Our `follows` wiring replaces that nixpkgs with the root's version. Narrow
evaluation confirms its default pnpm is **11.9.0**; `pnpm_10` is **10.34.4**,
not 10.13.1. Its fetcherVersion 3 recipe compresses the store into
`pnpm-store.tar.zst`, and its configure hook expects to extract that archive.
Thus changing only the pnpm binary cannot restore the old output layout or
guarantee the original hash. Fetching and offline installation must use a
matching pnpm version and fetcher/configure-hook pair.

There is a second reason not to adopt the observed v11 hash unchanged:
fetcherVersion 3 retains binary `index.db`. Nixpkgs explicitly introduced
fetcherVersion 4 to replace this database with a SQL dump for reproducibility
across machines. See [nixpkgs PR 522703](https://github.com/NixOS/nixpkgs/pull/522703).
The retained archive indeed contains the binary database, not `index.db.sql`.

These findings establish a builder/store-format incompatibility and no
dependency-integrity set drift. They do **not** establish which builder
originally produced the expected `oemBe...` hash, or that upstream kept that
hash current as its JavaScript lockfile changed.

### Original-builder replay

Replay only the dependency derivation using the pinned source as an independent
flake, so its own nixpkgs lock applies instead of the root's `follows` wiring:

```sh
nix build --impure --no-link --no-write-lock-file -L --expr '
  let
    upstream = builtins.getFlake
      "path:/nix/store/canx4iq89k3zl6n3gfwsrlhf78gm659k-source";
  in upstream.packages.x86_64-linux.default.pnpmDeps
'
```

This command was started on T2 as `aicommit-original-deps.service`. Its
output is in `/var/log/aicommit-original.out` and log in
`/var/log/aicommit-original.log`. It retains the original expected hash. If it passes,
the scoped fix should restore that locked pnpm 10.13.1 **and its original
fetcher/configure hook together**, preserving the current source and dependency
set. If it also mismatches, the upstream hash is stale for that baseline;
record its actual result before choosing a maintained pnpm 10 recipe or
pnpm 11 with fetcherVersion 4 and a deliberately regenerated hash.

No further code override or hash replacement was made in this follow-up:
the original-builder replay is required to distinguish a recoverable upstream
hash from a stale one. No builds or changes were made on T2.
