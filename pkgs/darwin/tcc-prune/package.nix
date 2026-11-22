{
  lib,
  python3,
  runCommand,
}:
runCommand "tcc-prune-0.1.0" {
  version = "0.1.0";
  meta = {
    description = "Report or delete stale macOS TCC grants (old /nix/store paths, uninstalled apps)";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [DivitMittal];
    platforms = lib.platforms.darwin;
    mainProgram = "tcc-prune";
  };
} ''
  mkdir -p $out/bin
  { echo '#!${python3.interpreter}'; cat ${./tcc-prune.py}; } > $out/bin/tcc-prune
  chmod +x $out/bin/tcc-prune
  ${python3.interpreter} -m py_compile $out/bin/tcc-prune
  rm -rf $out/bin/__pycache__
''
