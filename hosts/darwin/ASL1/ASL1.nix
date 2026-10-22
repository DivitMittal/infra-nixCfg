# Apple Silicon Darwin — mirrors L1 service layout via import-tree so new
# L1 modules are picked up automatically and internal renames don't break
# this host's build.
# Move shared pieces to common/hosts/darwin/ once configs diverge.
{inputs, ...}: {
  imports = [
    ../L1/defaults/defaults.nix
    (inputs.import-tree ../L1/programs)
    (inputs.import-tree ../L1/services)
  ];
}
