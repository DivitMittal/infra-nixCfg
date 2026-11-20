# Homelab Tailscale and Darwin build transport

## Observed state (2026-11-20)

Based on origin/master 10687584; review of PR75 and PR84 is read-only.
No deployment, activation, build on T2, or modification of another worktree.

- T1 (.3): SSH works; tailscaled inactive and no CLI found on PATH.
- T3 (.8): tailscaled inactive and no CLI found on PATH; atticd and
  attic-watch-store active. Anonymous LAN GETs for both infra/nix-cache-info
  and the current system's narinfo return HTTP 200. Treat infra as readable
  on the LAN; this does not prove Internet exposure or permission to upload
  private Darwin closures. No cache settings or tokens were changed.
- L1: current Home Manager wrapper invokes the GUI bundle;
  status does not return promptly. A standalone system CLI is absent.
  Enrollment and online state are unverified. PR84 changes the CLI to the
  standalone package; it is not merged here.
- Repository secrets: CACHIX_AUTH_TOKEN present. Environment dev:
  ATTIC_TOKEN, CACHIX_AUTH_TOKEN, SSH_PRIVATE_KEY, PAT present;
  TS_OAUTH_CLIENT_ID and TS_OAUTH_SECRET absent at both scopes.
  dev variable CACHE_ARTIFACT_RECIPIENT present (public recipient).
  Only names/presence were inspected, never credential values.
- CI-to-Attic push/pull cannot be verified without tailnet enrollment and
  credentials. Active LAN watcher alone is not proof of CI cache transport.

## Implemented behavior

T1 adopts PR75's optional encrypted auth key and advertises 192.168.2.0/24,
keeps DNS unchanged, and avoids NetworkManager ownership of tailscale0.
T3 is an ordinary client, advertises no subnet or exit-node routes, and
accepts neither routes nor DNS. T3 enrollment is manual until a separately
reviewed encrypted key is provisioned. Neither service is activated here.
T1 activation requires parent coordination because it routes the critical LAN.

Common CI cache setup accepts subnet routes on Linux, waits for a successful
Tailscale join, and writes its JWT to a mode-0600 config outside the store
instead of putting it in argv. Cache push requires successful setup. Pushes
of Darwin closures to `infra` stay disabled (`attic-push` skips macOS):
infra allows anonymous LAN reads, so it is unsuitable for private closures.

Darwin closures go to a separate private cache, `darwin`, on the same atticd
(remote `homelab`, substituter http://192.168.2.8:8080/darwin). On T3 the
`attic-darwin-cache` oneshot (hosts/nixos/T3/attic.nix,
hosts/nixos/T3/attic/provision-darwin.py) runs after atticd on every boot or
activation and is idempotent: it creates `darwin` with `is_public = false`
and a server-generated signing key when it is missing, re-asserts
`is_public = false` when it exists (never regenerating the keypair), checks
that an anonymous GET of `darwin/nix-cache-info` is denied, and writes the
public verification key to /var/lib/attic-darwin-cache/public-key (also
printed in the journal). It mints only a ten-minute in-memory bootstrap token
(pull, create-cache, configure-cache on `darwin`); it never mints, logs or
stores CI tokens, and never touches `infra`.

The separate darwin-offload workflow is manual, builds L1 or ASL1 Darwin
and Home Manager closures on native runners (macos-15-intel for L1,
macos-15 Apple Silicon for ASL1), and never activates them.
The target is allowlisted and host architecture checked; both builds use max-jobs=2/cores=2, and timeout
is six hours. This job excludes Magic Nix Cache uploads and the shared infra
Attic setup; Cachix remains pull-only.

When ATTIC_DARWIN_TOKEN, TS_OAUTH_CLIENT_ID, TS_OAUTH_SECRET and the
DARWIN_CACHE_PUBLIC_KEY variable are all present, the job joins the tailnet
and runs flake/actions/darwin-cache.py, which refuses to continue unless
`darwin` exists, reports `is_public: false`, serves the pinned public key at
the expected endpoints, and denies anonymous reads. It then pushes a harmless
probe path, checks the probe's narinfo is denied anonymously, pulls it into
an independent store with `require-sigs` and only the pinned key trusted,
and only then pushes both closures with `attic push homelab:darwin` and
confirms them with `nix path-info`. Every private-cache step is
`continue-on-error`.

If any of those steps does not succeed (secret absent, T3 offline, ACL
missing), the existing fallback runs: both closures are exported together,
compressed, and age-encrypted before artifact upload. Only public recipient,
output paths, and source SHA accompany the encrypted artifact (three-day
retention). CACHE_ARTIFACT_RECIPIENT is still required before building so
the fallback is always available. Invalid recipients fail encryption and
produce no upload. The runner never receives the decryption key.

The workflow intentionally does not import PR84's lock refresh or package
changes. Current master may still fail Intel evaluation until the separate
PR84 compatibility work is resolved. Building both target outputs also
requires the corresponding outputs to evaluate on this pinned revision.

## Credential and policy handoff

The personal tailnet policy, router auto-approval and dedicated CI OAuth
client are now declared through the Tailscale provider. Follow
[tailscale.md](tailscale.md) for policy adoption, encrypted state,
credential export and the forge-tofu handoff. Manual console creation is
only needed to bootstrap the operator identity; do not maintain a second
policy alongside the provider. CI receives only the auth-key identity for
`tag:ci`, with access to TCP 192.168.2.8:8080.

ATTIC_TOKEN already exists and stays scoped to infra. If replacing it, the
server operator should issue a token with pull and push only for infra; no
create-cache, configure-cache, destroy-cache or wildcard permissions. Attic
credentials are minted by atticadm on T3, not an external website. Keep the
existing signature check and pinned public keys on clients; never set
require-sigs=false. A public verification key is not a token.

## Private darwin cache: one-time operator steps

Names used by CI (environment `dev`):

| Name                       | Kind     | Content                                        |
| -------------------------- | -------- | ---------------------------------------------- |
| `ATTIC_DARWIN_TOKEN`       | secret   | JWT with `--pull darwin --push darwin` only    |
| `DARWIN_CACHE_PUBLIC_KEY`  | variable | `darwin:<base64>` from T3 (public, not secret) |
| `TS_OAUTH_CLIENT_ID`       | secret   | Tailscale OAuth client (see above)             |
| `TS_OAUTH_SECRET`          | secret   | Tailscale OAuth secret (see above)             |
| `CACHE_ARTIFACT_RECIPIENT` | variable | age recipient for the encrypted fallback       |

1. After T3 is deployed with this change, confirm the cache is private and
   read its public key (the unit runs automatically; `start` is idempotent):

   ```bash
   ssh T3 'sudo systemctl start attic-darwin-cache && systemctl status --no-pager attic-darwin-cache'
   ssh T3 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/darwin/nix-cache-info'   # expect 401/403/404
   ssh T3 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/infra/nix-cache-info'    # still 200
   ssh T3 cat /var/lib/attic-darwin-cache/public-key \
     | gh variable set DARWIN_CACHE_PUBLIC_KEY --env dev --repo DivitMittal/infra-nixCfg
   ```

   Manual equivalent of the unit, with an admin-scoped `attic` login:
   `attic cache create homelab:darwin` (private unless `--public`), then
   `attic cache configure --private homelab:darwin`, and
   `attic cache info homelab:darwin` for the public key.

2. Mint the CI token on T3 and pipe it straight into the GitHub secret. The
   token goes over ssh stdout into `gh`'s stdin: never argv, a file in git,
   the store or a log. `atticd-atticadm` is the NixOS module's wrapper (it
   loads the server config and RS256 secret). With passwordless sudo:

   ```bash
   ssh T3 'sudo atticd-atticadm make-token --sub github-darwin-ci --validity 90d --pull darwin --push darwin' \
     | gh secret set ATTIC_DARWIN_TOKEN --env dev --repo DivitMittal/infra-nixCfg
   ```

   If sudo asks for a password, mint into a user-owned tmpfs file in an
   interactive session, then move it and delete it in one non-interactive one:

   ```bash
   ssh -t T3 'umask 077; sudo atticd-atticadm make-token --sub github-darwin-ci --validity 90d --pull darwin --push darwin > /dev/shm/attic-darwin-ci.token'
   ssh T3 'cat /dev/shm/attic-darwin-ci.token; rm -f /dev/shm/attic-darwin-ci.token' \
     | gh secret set ATTIC_DARWIN_TOKEN --env dev --repo DivitMittal/infra-nixCfg
   ```

   Do not add `--create-cache`, `--configure-cache`, `--delete`,
   `--destroy-cache`, or any pattern other than `darwin` (no `*`, no
   `infra`). Rotate by re-running before the 90 days run out; revoking early
   requires rotating ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64, which also
   invalidates every infra token.

3. Optional, for hosts that substitute from `darwin` (L1/ASL1): a pull-only
   token, `--sub darwin-import --validity 90d --pull darwin`, kept in that
   host's ragenix secret or netrc, never in this repository.

4. Dispatch the workflow and check the step summary for "Both Darwin
   closures are present in the private signed cache":

   ```bash
   gh workflow run darwin-offload.yml --ref <branch> -f target=L1
   ```

Never import the encrypted fallback artifact on T2 or T3:
attic-watch-store there pushes every new store path to `infra`, which
is anonymously readable.

For encrypted transport, dev variable CACHE_ARTIFACT_RECIPIENT contains the
importer's public age/SSH recipient. Its matching private key stays on the
import machine. SSH_PRIVATE_KEY must have read access to required private
flake repositories only; prefer read-only deploy keys per repository over
an account-wide key. PAT is not used by the new workflow.

## Verification and operator steps

Use native eval.yml for T1/T3 and L1/ASL1; do not run whole-configuration
local evaluation or flake checks. CI runs builds only when separately
requested; a PR evaluation is not a deployment build. Coordinate parent
before any deployment build on T2 (max-jobs=2/cores=2).

After merge and successful native evaluation, parent can manually dispatch
Darwin offload, inspect the two output paths/source SHA, and download the
encrypted artifact. On an authorized import machine, with its local age key:

```bash
age -d -i /path/to/local/identity deployment.nar.zst.age | zstd -d | nix-store --import
```

Run the pipeline with `set -o pipefail`; importing registers paths without
activation. The age recipient authenticates confidentiality, not provenance:
verify repository, exact workflow run, commit SHA and output paths before
trusting an export (store exports are not the signed Attic substitution
protocol). Do not execute activation scripts as part of transport testing.

Once connectivity exists, demonstrate push/pull using a reviewed harmless
probe path first: authenticated push from a runner, signed narinfo lookup,
then substitution into an independent store with signature checks enabled.
Do not label a skipped optional step or an HTTP 200 alone as push/pull success.

## Primary references

- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://github.com/actions/runner-images/blob/main/README.md
- https://tailscale.com/docs/integrations/github/github-action
- https://raw.githubusercontent.com/tailscale/github-action/v3/action.yml
- https://docs.attic.rs/reference/attic-cli.html
- https://docs.attic.rs/tutorial.html

GitHub's current runner table includes macos-15-intel (native Intel Darwin);
macos-13 is retired. No macOS VM on a non-Apple homelab host is proposed.

## Local validation record

`nix fmt`, workflow generation with `nix run .#render-workflows`, and
`git diff --check` pass. The new darwin-offload workflow passes actionlint
including ShellCheck. All rendered workflows pass actionlint's structural
checks (`-shellcheck=`); a full-repository ShellCheck pass still reports
pre-existing LOCAL_OVERRIDES word-splitting and eval-script style warnings.
`nix-store --export --stdin` accepts stdin on the local Nix installation.
No whole-configuration local checks or deployment builds were run.
Parent reports PR91 observed L1's default route through T1's router; this
is routing evidence, not proof of Tailscale login. Parent owns credential
UI/secure capture and is building T3/MON1; no competing heavy build here.

A harmless store-export probe passed an export → zstd → age → decrypt →
decompress byte-for-byte roundtrip with a temporary local identity. No
private closure or credential was used; temporary identity files were deleted.

Private darwin cache change: `nix fmt`, `nix run .#render-workflows`,
`git diff --check` and actionlint on darwin-offload.yml pass; both Python
helpers byte-compile. Neither the oneshot nor the CI path ran against the
live server; T3 was not deployed and no token was minted.
