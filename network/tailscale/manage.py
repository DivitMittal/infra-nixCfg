"""Operate the personal tailnet from a private, tailnet-specific state directory."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def request(url, headers, data=None):
    req = urllib.request.Request(url, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Tailscale API returned HTTP {error.code}; response withheld") from None


def credential(name):
    value = os.environ.get(name, "")
    return Path(value[5:]).read_text().strip() if value.startswith("file:") else value


def api_headers():
    key = credential("TAILSCALE_API_KEY")
    if not key:
        client = credential("TAILSCALE_OAUTH_CLIENT_ID")
        secret = credential("TAILSCALE_OAUTH_CLIENT_SECRET")
        if not client or not secret:
            raise RuntimeError("Supply a policy-reading Tailscale API key or OAuth credentials")
        payload = urllib.parse.urlencode({
            "grant_type": "client_credentials", "client_id": client, "client_secret": secret,
        }).encode()
        key = request("https://api.tailscale.com/api/v2/oauth/token", {
            "Content-Type": "application/x-www-form-urlencoded",
        }, payload)["access_token"]
    return {"Authorization": "Bearer " + key, "Accept": "application/json"}


def snapshot(directory, tailnet):
    target = directory / "policy-baseline.json"
    if target.exists():
        raise RuntimeError("Policy baseline exists; review it instead of overwriting it")
    policy = request(
        "https://api.tailscale.com/api/v2/tailnet/" + urllib.parse.quote(tailnet, safe="") + "/acl",
        api_headers(),
    )
    if not isinstance(policy, dict):
        raise RuntimeError("API did not return a JSON policy object")
    with target.open("x") as out:
        json.dump(policy, out, indent=2)
        out.write("\n")
    print(f"Saved existing policy to {target}. Review before planning.")


def export_secrets(directory):
    recipient = os.environ.get("TAILSCALE_AGE_RECIPIENT", "")
    destination = os.environ.get("TAILSCALE_SECRETS_DIR", "")
    if not recipient or not destination:
        raise RuntimeError("Set TAILSCALE_AGE_RECIPIENT and TAILSCALE_SECRETS_DIR (the private repo's secrets directory)")
    result = subprocess.run(["tofu", "output", "-json"], cwd=directory, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("Cannot read encrypted state outputs; command output withheld")
    outputs = json.loads(result.stdout)
    files = {
        "ci_client_id": "ci/infra-nixCfg/ts_oauth_client_id.age",
        "ci_client_secret": "ci/infra-nixCfg/ts_oauth_secret.age",
        "t1_auth_key": Path("homelab") / "T1-tailscale.age",
    }
    # Check every destination first; exporting must never replace existing keys.
    for name, relative in files.items():
        if (Path(destination) / relative).exists():
            raise RuntimeError(f"Encrypted destination already exists: {relative}")
        if not outputs.get(name, {}).get("value"):
            raise RuntimeError(f"Missing output {name}; import cannot recover generated secrets")
    for name, relative in files.items():
        target = Path(destination) / relative
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        encrypted = subprocess.run(
            ["rage", "--encrypt", "--recipient", recipient],
            input=outputs[name]["value"].encode(), capture_output=True, check=False,
        )
        if encrypted.returncode:
            raise RuntimeError("Encryption failed; command output withheld")
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as out:
            out.write(encrypted.stdout)
        print(f"Wrote encrypted {target}")


def main():
    os.umask(0o077)
    mode = sys.argv[1] if len(sys.argv) > 1 else "plan"
    allowed = {"snapshot", "init", "validate", "plan", "rotate-t1", "import-lan-dns", "apply", "show", "export-secrets"}
    if mode not in allowed or len(sys.argv) > 2:
        raise RuntimeError("Usage: tailscale-personal [snapshot|init|validate|plan|rotate-t1|import-lan-dns|apply|show|export-secrets]")
    tailnet = os.environ.get("TAILSCALE_TAILNET", "").strip()
    if not tailnet:
        raise RuntimeError("Set TAILSCALE_TAILNET explicitly to the personal tailnet ID")
    # A different account must never reuse this tailnet's state or policy baseline.
    account = hashlib.sha256(tailnet.encode()).hexdigest()[:20]
    state_root = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    directory = state_root / "infra-nixCfg/tofu/tailscale" / account
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    if mode == "snapshot":
        snapshot(directory, tailnet)
        return
    passphrase = os.environ.get("TF_VAR_state_passphrase", "")
    if len(passphrase) < 32:
        raise RuntimeError("Supply TF_VAR_state_passphrase (at least 32 characters); retain it for state recovery")
    shutil.copyfile(os.environ["TAILSCALE_TF_CONFIG"], directory / "config.tf.json")
    if mode in {"init", "validate"}:
        if mode == "init":
            shutil.copyfile(os.environ["TAILSCALE_TF_LOCK"], directory / ".terraform.lock.hcl")
        subprocess.run(["tofu", mode], cwd=directory, check=True)
        return
    baseline = directory / "policy-baseline.json"
    if not baseline.is_file():
        raise RuntimeError("Run snapshot, then review policy-baseline.json before planning")
    os.environ["TF_VAR_base_policy"] = baseline.read_text()
    if mode == "export-secrets":
        export_secrets(directory)
        return
    if mode == "import-lan-dns":
        if os.environ.get("TF_VAR_enable_lan_dns") != "true":
            raise RuntimeError("Set TF_VAR_enable_lan_dns=true before importing the existing .lan resolver")
        subprocess.run(["tofu", "import", "tailscale_dns_split_nameservers.lan[0]", "lan"], cwd=directory, check=True)
        return
    plan = directory / "reviewed.tfplan"
    if mode in {"plan", "rotate-t1"}:
        # Remove an older plan so a failed plan cannot leave an applicable artifact.
        plan.unlink(missing_ok=True)
        args = ["plan", "-out=" + str(plan)]
        if mode == "rotate-t1":
            args.append("-replace=tailscale_tailnet_key.t1")
    elif mode == "apply":
        if not plan.is_file():
            raise RuntimeError("Run plan and review the saved plan before apply")
        args = ["apply", str(plan)]
    else:
        args = ["show", str(plan)]
    try:
        subprocess.run(["tofu", *args], cwd=directory, check=True)
    finally:
        if mode == "apply":
            plan.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        # API errors and credential-export subprocess failures never include bodies.
        print(f"tailscale-personal: {error}", file=sys.stderr)
        raise SystemExit(1) from None
