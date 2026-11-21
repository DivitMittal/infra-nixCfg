{
  lib,
  python3,
  runCommand,
  writeShellApplication,
}: let
  fixtures = runCommand "homelab-dash-probe-fixtures" {nativeBuildInputs = [python3];} ''
    cp ${./probe.py} probe.py
    cp ${./test_probe.py} test_probe.py
    python3 -B -m unittest -v test_probe
    touch $out
  '';
in
  writeShellApplication {
    name = "homelab-dash-probe";
    runtimeInputs = [python3];
    text = ''
      exec python3 ${./probe.py} "$@"
    '';
    derivationArgs = {
      passthru.tests = {inherit fixtures;};
      meta = {
        description = "Bounded unauthenticated WS-Man Identify probe for DASH discovery";
        license = lib.licenses.mit;
      };
    };
  }
