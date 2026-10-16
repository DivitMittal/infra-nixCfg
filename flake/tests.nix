# Test suites exposed as flake checks.
#
# Nix suites (tests/*.nix) are `lib.debug.runTests` attrsets. Failures throw at
# evaluation time, so they surface even under CI's `nix flake check --no-build`.
# Shell suites (tests/shell/*.bats) and shellcheck need a build:
#   nix build .#checks.<system>.shell-tests
{
  inputs,
  lib,
  self,
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
      // lib.optionalAttrs isDarwin {
        tests-modules-darwin = mkEvalCheck "modules-darwin" (suite ../tests/modules-darwin.nix);
      };
  };
}
