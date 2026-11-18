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
