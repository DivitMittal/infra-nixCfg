# Personal tailnet

The personal tailnet is owned by `infra-nixCfg`, with one policy resource and
one encrypted OpenTofu state. `network/tailscale/personal.nix` declares the
control plane; `flake/tailscale.nix` exposes its JSON and command. Host daemon
settings remain in `hosts/nixos/{T1,T3}/tailscale.nix`. Qezta-owned tailnets
belong in Qezta/infra. Never manage the same tailnet policy from both repos.

## Requirements

Use `nix run .#tailscale-personal -- <command>`. Nix supplies OpenTofu,
Python and rage; OpenTofu init downloads the pinned official Tailscale
provider using the committed provider checksum lock. The command requires `TAILSCALE_TAILNET` to identify the personal
tailnet explicitly. Authenticate with `TAILSCALE_API_KEY`, or
`TAILSCALE_OAUTH_CLIENT_ID` and `TAILSCALE_OAUTH_CLIENT_SECRET`. The bootstrap
identity needs policy read/write and authority to create the declared OAuth
client and tagged auth key. It stays on the operator's machine; it is never
the restricted CI identity. Provider credentials can use `file:/absolute/path`.

Supply `TF_VAR_state_passphrase` at runtime from a secret manager or an
age-encrypted file. Use at least 32 random characters and retain it for
recovery. Do not generate a different passphrase on every invocation.
State and saved plans use enforced OpenTofu PBKDF2/AES-GCM encryption.
Their private directory is under
`${XDG_STATE_HOME:-$HOME/.local/state}/infra-nixCfg/tofu/tailscale/<tailnet-hash>`;
separate tailnets cannot accidentally share a state or baseline. Local state
locking applies. Back up the encrypted state, provider lock file and policy
baseline; retain the passphrase separately. A shared remote backend is a
future migration, not a prerequisite for this operator-managed stack.

## Adopt existing policy

```bash
nix run .#tailscale-personal -- snapshot
# Review the printed policy-baseline.json path before proceeding.
nix run .#tailscale-personal -- init
nix run .#tailscale-personal -- validate
nix run .#tailscale-personal -- plan
nix run .#tailscale-personal -- show
nix run .#tailscale-personal -- apply
```

`snapshot` is read-only against Tailscale and refuses to overwrite an existing
baseline. It requests JSON, preserving existing groups, access rules, SSH
policy, hosts, tests and other policy sections. Review and retain this
baseline privately. It is a required input, with no default empty policy.
The import block adopts the existing policy before changing it; it does not
bypass the provider's overwrite protection. Policy destruction is prevented.
A failed plan removes any old saved plan; apply accepts only the saved plan
and removes it after an attempt. These commands do not activate any host.

The resulting policy adds:

- `tag:homelab-router`, owned by tailnet admins, for T1 alone.
- Automatic approval of `192.168.2.0/24` for that router tag.
- Admin ownership for `tag:ci`, preserving any existing owners.
- A grant from `tag:ci` to TCP `192.168.2.8:8080`.
- Policy tests allowing the cache and denying sample LAN management ports.

Existing grants are additive in Tailscale. If the baseline has a wildcard
allow-all rule, the negative CI tests will fail during the provider plan.
Review and narrow that baseline rule explicitly before applying; the command
does not silently remove other users' access. Console edits after adoption
are drift and should be reconciled into the baseline/declaration.

`.lan` split DNS is opt-in with `TF_VAR_enable_lan_dns=true`; it sends that
suffix to `192.168.2.1`. Import an existing matching resolver before enabling
management (resource address `tailscale_dns_split_nameservers.lan[0]`, ID
`lan`) with `nix run .#tailscale-personal -- import-lan-dns`. Do not change global
DNS or MagicDNS ownership merely to reach the numeric cache endpoint. Remote
users also need grants permitting access to the resolver; CI does not.

## Credential handoff

The provider creates an `auth_keys` OAuth client limited to `tag:ci` and a
single-use, preauthorized, non-ephemeral T1 auth key tagged
`tag:homelab-router`. T1's enrollment key expires after one hour and is not
recreated when consumed. Apply when ready to enroll T1; if enrollment is
missed, run `nix run .#tailscale-personal -- rotate-t1`, review the saved replacement
plan, then apply it. Enrollment-key expiry is
separate from an enrolled device's node-key expiry.

Set `TAILSCALE_AGE_RECIPIENT` to the existing private secrets repository's
public recipient, and `TAILSCALE_SECRETS_DIR` to that checkout's `secrets`
directory, then run:

```bash
nix run .#tailscale-personal -- export-secrets
```

The command captures sensitive outputs in memory, feeds them to rage over
stdin, and writes only encrypted files:

- `ci/infra-nixCfg/ts_oauth_client_id.age`
- `ci/infra-nixCfg/ts_oauth_secret.age`
- `homelab/T1-tailscale.age`

Existing files are never overwritten. Register the recipients in the private
secrets manifest, commit those encrypted files, and update the secrets input
before deploying T1. Importing an existing OAuth client cannot recover its
secret; the provider generates a new dedicated client here.

`forge-tofu` owns delivery to the existing `infra-nixCfg` GitHub `dev`
environment. Move `TS_OAUTH_CLIENT_ID` and `TS_OAUTH_SECRET` from its
`pending_secrets` to `secrets` and enable the matching encrypted source paths
after these files exist. Review the forge plan; no networking state is shared
with it. Other live GitHub secrets remain untouched while pending.

## Deployment verification

After configuration merge and successful native evaluations, deploy T1 with
its encrypted enrollment key, confirm it has `tag:homelab-router`, and verify
its subnet route is approved. T3 enrollment is optional for the existing
LAN-address cache endpoint: the CI path remains runner → T1 → T3. That final
HTTP LAN hop is outside the Tailscale tunnel. T3's ordinary client does not
change this endpoint automatically.

Verify a runner can reach TCP 192.168.2.8:8080 and cannot reach the denied
management ports. Prove cache transport with a harmless authenticated push
and independent signed pull. Successful evaluation, tailnet login, or a
skipped optional cache step is not that proof. The upstream v3 GitHub action
already accepts subnet routes; the explicit CI setting reinforces it.

The separate private Darwin cache and encrypted artifact fallback are
documented in [homelab-build-cache.md](homelab-build-cache.md).

## References

- [Official provider](https://registry.terraform.io/providers/tailscale/tailscale/0.30.0/docs)
- [Full-policy ownership](https://github.com/tailscale/terraform-provider-tailscale/blob/v0.30.0/docs/resources/acl.md)
- [OpenTofu encryption](https://opentofu.org/docs/language/state/encryption/)
