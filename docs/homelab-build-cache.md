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
instead of putting it in argv. Cache push requires successful setup. Darwin
pushes and automatic eval-job Darwin builds/pushes are disabled: infra's
anonymous LAN reads are unsuitable for unreviewed private Darwin closures.

The separate darwin-offload workflow is manual, builds L1 or ASL1 Darwin
and Home Manager closures on native runners (macos-15-intel for L1,
macos-15 Apple Silicon for ASL1), and never activates them.
The target is allowlisted and host architecture checked; both builds use max-jobs=2/cores=2, and timeout
is six hours. This job excludes Magic Nix Cache uploads and Attic setup;
Cachix remains pull-only. Both closures are exported together, compressed,
and age-encrypted before artifact upload. Only public recipient, output
paths, and source SHA accompany the encrypted artifact (three-day retention).
A missing recipient fails before building. Invalid recipients fail encryption
and produce no upload. The runner never receives the decryption key.

The workflow intentionally does not import PR84's lock refresh or package
changes. Current master may still fail Intel evaluation until the separate
PR84 compatibility work is resolved. Building both target outputs also
requires the corresponding outputs to evaluate on this pinned revision.

## Credential and policy handoff

Use https://login.tailscale.com/admin/settings/oauth for a CI OAuth client.
Select Auth Keys: Write (auth_keys), restricted to tag:ci; do not grant
policy, DNS, route, or general device administration. Put Client ID and
Client secret directly into dev environment secrets TS_OAUTH_CLIENT_ID
and TS_OAUTH_SECRET at:
https://github.com/DivitMittal/infra-nixCfg/settings/environments
(select dev). Do not paste credentials into chat or files in this repo.
Existing v3 action accepts these OAuth fields; migration to v4/OIDC is
separate work, not required to unblock this configuration.

At https://login.tailscale.com/admin/acls define tag:ci and a T1-only
subnet-router tag with admin ownership. Grant tag:ci only TCP
192.168.2.8:8080, rather than the entire LAN. Approve 192.168.2.0/24
on T1 at https://login.tailscale.com/admin/machines (or use autoApprovers
restricted to the T1 tag). A grant to port 8080 does not grant LAN SSH.
For T1 automatic enrollment, create a non-ephemeral, pre-approved,
non-reusable key tagged for the router at
https://login.tailscale.com/admin/settings/keys and encrypt directly with
ragenix into the private secrets input at secrets/homelab/T1-tailscale.age.
No plaintext auth key belongs in this repository or the Nix store.
When the key is absent, coordinate `tailscale up` enrollment with parent;
the module still enables the daemon and applies route settings.

ATTIC_TOKEN already exists. If replacing it, the server operator should
issue a short-lived token with pull and push only for infra (or a future
reviewed private Darwin cache); no create-cache, configure-cache,
destroy-cache or wildcard permissions. Attic credentials are minted by
atticadm on T3, not an external website. Cache privacy/signing changes and
any Darwin cache publication must be reviewed separately before enabling.
Keep the existing signature check and pinned infra public key on clients;
never set require-sigs=false. A public verification key is not a token.

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
