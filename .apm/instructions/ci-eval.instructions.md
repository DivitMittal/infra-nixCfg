---
description: Evaluate configurations on GitHub Actions native runners, not on the local machine
applyTo: "**"
---

# EVALUATING CHANGES (CI, NOT LOCAL)

## RULE

Do not run heavy local evaluation or builds to check a change: no
`nix build`/`nix eval` of whole `nixosConfigurations`, `darwinConfigurations` or
`homeConfigurations`, and no `nix flake check`. These use a lot of local
hardware, and only a native runner can realise each system's
import-from-derivation (IFD). Use `.github/workflows/eval.yml` instead. It
evaluates each configuration's `drvPath` on a runner of its own system
(ubuntu x86/arm, macos intel/arm) and builds nothing.

Cheap local commands are still fine: `nix fmt`, `nix flake lock` /
`nix flake update <input>`, `nix run .#render-workflows`, and evaluating a
single small attribute.

## HOW

- **Open PR to master:** eval runs automatically on every push.
- **No PR, or a stacked/WIP commit:** push the commit to a throwaway branch
  named `eval/<topic>`, e.g. `git push origin HEAD:eval/vicinae`. The branch must
  contain `eval.yml` (any branch based on current master does). Delete the
  branch when you're done: `git push origin --delete eval/<topic>`.
- **Only some targets:** add an `Eval-Filter:` trailer to the head commit. Its
  value is a regex matched against attrs such as
  `homeConfigurations.L1.activationPackage`:

  ```
  Eval-Filter: ^homeConfigurations\.(L1|ASL1)\.
  ```

  Or run it manually: `gh workflow run eval.yml --ref <branch> -f filter='<regex>'`.

- **Results:** `gh run list --branch <branch> --workflow eval.yml`, then
  `gh run view <id> --log-failed`. Each target is its own job, named after its
  attr.

## NOTES

- Evaluation stops at the first error. Fixing one failure can reveal another
  behind it, so re-run until the job you care about passes.
- Inputs locked to local checkouts (`path:`/`git+file:`) are rewritten to their
  GitHub repos in CI. Push changes to those repos (a branch is enough) before
  relying on CI, e.g. lock to the branch head with
  `nix flake lock --override-input <input> github:DivitMittal/<repo>/<rev>`.
- `nix flake check` in CI runs natively on x86_64-linux only. `--no-build` is
  read-only and fails with `path ... is not valid` (NixOS/nix#15448).
