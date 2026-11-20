#!/usr/bin/env python3
"""Fetch an exact successful CI deployment from the signed private cache."""

import argparse
import json
from pathlib import Path
import platform
import re
import shlex
import subprocess
import tempfile


REPOSITORY = "DivitMittal/infra-nixCfg"
CACHE = "http://192.168.2.8:8080/darwin"
PUBLIC_KEY = "darwin:M23zZ3tCyh8PKSIwtRe5mrTYja5qChQAWJL6IquQTEk="


def pull(run, target):
    expected_arch = {"L1": "x86_64", "ASL1": "arm64"}[target]
    if platform.system() != "Darwin" or platform.machine() != expected_arch:
        raise RuntimeError(f"{target} requires a native {expected_arch} Mac")
    metadata = json.loads(subprocess.check_output([
        "gh", "run", "view", str(run), "--repo", REPOSITORY,
        "--json", "conclusion,headSha,workflowName",
    ]))
    if metadata["conclusion"] != "success":
        raise RuntimeError("The deployment workflow must finish successfully first")
    if metadata["workflowName"] != ".github/workflows/darwin-offload.yml":
        raise RuntimeError("Run is not the Darwin offload workflow")
    revision = metadata["headSha"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("Unexpected source revision")
    with tempfile.TemporaryDirectory(prefix="darwin-deployment-") as temporary:
        directory = Path(temporary)
        subprocess.run([
            "gh", "run", "download", str(run), "--repo", REPOSITORY,
            "--name", f"darwin-{target}-{revision}", "--dir", str(directory),
        ], check=True)
        if (directory / "source-revision.txt").read_text().strip() != revision:
            raise RuntimeError("Artifact revision differs from the workflow revision")
        if (directory / "deployment.nar.zst.age").exists():
            raise RuntimeError("This run used encrypted artifact fallback; see docs/homelab-build-cache.md")
        paths = (directory / "deployment-paths.txt").read_text().splitlines()
        if len(paths) != 2 or any(
            not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^/\s]+", path) for path in paths
        ):
            raise RuntimeError("Expected exactly two deployment store paths")
        subprocess.run([
            "nix", "copy", "--from", CACHE,
            "--option", "require-sigs", "true",
            "--option", "trusted-public-keys", PUBLIC_KEY,
            "--option", "netrc-file", str(Path.home() / ".config/nix/darwin-cache.netrc"),
            *paths,
        ], check=True)
        if any(not (Path(path) / "activate").is_file() for path in paths):
            raise RuntimeError("Downloaded outputs do not contain both activation scripts")
    print(f"Downloaded {target} system and home closures from {revision}.")
    print("Activate the system:")
    print(shlex.join(["sudo", "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", paths[0]]))
    print(shlex.join(["sudo", paths[0] + "/activate"]))
    print("Activate Home Manager:")
    print(shlex.join([paths[1] + "/activate"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=int, help="Successful darwin-offload GitHub Actions run ID")
    parser.add_argument("--target", choices=["L1", "ASL1"], default="L1")
    args = parser.parse_args()
    try:
        pull(args.run, args.target)
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"darwin_cached_pull: {error}\n")


if __name__ == "__main__":
    main()
