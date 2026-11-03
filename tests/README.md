# tests

Test suites wired into `nix flake check` by `flake/tests.nix`.

| Check                  | Suite                | Covers                                                          |
| ---------------------- | -------------------- | --------------------------------------------------------------- |
| `tests-lib`            | `lib.nix`            | `lib/custom.nix` helpers, `lib/palette.nix` shape               |
| `tests-hosts`          | `hosts.nix`          | `hosts/*` ↔ configuration outputs ↔ home configs ↔ deploy nodes |
| `tests-packages`       | `packages.nix`       | `pkgs/*` exposure via the overlay, package metadata             |
| `tests-modules-home`   | `modules-home.nix`   | `modules/home/*` evaluated through home-manager                 |
| `tests-modules-darwin` | `modules-darwin.nix` | `modules/hosts/darwin/*` evaluated through nix-darwin (darwin)  |
| `shellcheck`           | —                    | `utils/*.sh`, `tests/shell/*.bash`                              |
| `shell-tests`          | `shell/*.bats`       | `utils/*.sh` with every external command stubbed                |

The Nix suites are `lib.debug.runTests` attrsets. Failures throw during
evaluation, so they also fail CI's `nix flake check --no-build`. The shell
suites need a build:

```bash
nix build .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).shell-tests
```

Adding a test: add a `testFoo = { expr = ...; expected = ...; };` entry to the
matching suite, or a `@test` to the matching `.bats` file. New suites go in
`flake/tests.nix`.
