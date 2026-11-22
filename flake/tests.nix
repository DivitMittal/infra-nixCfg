# Test suites exposed as flake checks.
#
# Nix suites (tests/*.nix) are `lib.debug.runTests` attrsets; failures throw at
# evaluation time with the expected/got values. Shell suites (tests/shell/*.bats)
# and shellcheck are builds. CI's flake-check job runs `nix flake check` on
# x86_64-linux, which covers all of them. One at a time:
#   nix build .#checks.<system>.shell-tests
{
  inputs,
  lib,
  self,
  withSystem,
  ...
}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs.stdenv.hostPlatform) isDarwin;

    mkEvalCheck = name: tests: let
      failures = lib.debug.runTests tests;
      report = lib.concatMapStringsSep "\n" (f: "  ${f.name}\n    expected: ${lib.generators.toPretty {} f.expected}\n    got:      ${lib.generators.toPretty {} f.result}") failures;
    in
      if failures == []
      then pkgs.runCommandLocal "tests-${name}" {} "echo ${toString (lib.length (lib.attrNames tests))} passed > $out"
      else throw "tests-${name}: ${toString (lib.length failures)} failing:\n${report}";

    args = {inherit lib pkgs inputs self;};
    suite = file: import file (builtins.intersectAttrs (lib.functionArgs (import file)) args);

    scripts = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [../utils ../tests/shell];
    };
  in {
    checks =
      {
        tests-lib = mkEvalCheck "lib" (suite ../tests/lib.nix);
        tests-hosts = mkEvalCheck "hosts" (suite ../tests/hosts.nix);
        tests-packages = mkEvalCheck "packages" (suite ../tests/packages.nix);
        tests-modules-home = mkEvalCheck "modules-home" (suite ../tests/modules-home.nix);

        shellcheck = pkgs.runCommandLocal "shellcheck" {nativeBuildInputs = [pkgs.shellcheck];} ''
          cd ${scripts}
          shellcheck --severity=warning --external-sources --source-path=utils utils/*.sh tests/shell/*.bash
          touch $out
        '';

        shell-tests = pkgs.runCommandLocal "shell-tests" {nativeBuildInputs = [pkgs.bats pkgs.git];} ''
          export HOME=$TMPDIR
          bats --print-output-on-failure ${scripts}/tests/shell
          touch $out
        '';
      }
      // {
        ## Eval-only, so Linux evaluates it against aarch64-darwin pkgs: CI's
        ## `nix flake check` runs on a Linux runner, and eval.yml never runs
        ## checks, so a darwin-only check would never run in CI.
        tests-modules-darwin = mkEvalCheck "modules-darwin" (
          if isDarwin
          then suite ../tests/modules-darwin.nix
          else withSystem "aarch64-darwin" ({pkgs, ...}: import ../tests/modules-darwin.nix (args // {inherit pkgs;}))
        );
      };
  };
}
