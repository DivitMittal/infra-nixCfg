# Structural invariants between hosts/, the configuration outputs and deploy-rs.
# Only attribute names and plain strings are forced, so no host is fully
# evaluated and the private secrets input is never touched.
{
  lib,
  self,
}: let
  hostDirs = class:
    lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir (self + "/hosts/${class}")));

  sorted = lib.sort lib.lessThan;
  missingFrom = attrs: names: lib.filter (n: !(attrs ? ${n})) names;

  nixos = self.nixosConfigurations;
  darwin = self.darwinConfigurations;
  droid = self.nixOnDroidConfigurations;
  home = self.homeConfigurations;
  nodes = self.deploy.nodes;

  ## colima-arm reuses hosts/nixos/colima (hostName = "colima").
  variants = {colima-arm = "colima";};
  hostDirOf = name: variants.${name} or name;

  systemHosts = lib.attrNames darwin ++ lib.attrNames droid ++ lib.subtractLists (hostDirs "iso") (lib.attrNames nixos);
  nodeNames = lib.attrNames nodes;
  homeNodes = lib.filter (lib.hasSuffix "-home") nodeNames;
  systemNodes = lib.subtractLists homeNodes nodeNames;
  ## Deploy node -> configuration it activates (M1-adb is M1 over ADB).
  configOfNode = name: lib.removeSuffix "-adb" (lib.removeSuffix "-home" name);
in {
  ## ── every host directory is wired into an output ──────────────────────────
  testEveryNixosHostDirHasConfiguration = {
    expr = missingFrom nixos (hostDirs "nixos");
    expected = [];
  };

  testEveryDarwinHostDirHasConfiguration = {
    expr = missingFrom darwin (hostDirs "darwin");
    expected = [];
  };

  testEveryDroidHostDirHasConfiguration = {
    expr = missingFrom droid (hostDirs "droid");
    expected = [];
  };

  testEveryIsoHostDirHasConfiguration = {
    expr = missingFrom nixos (hostDirs "iso");
    expected = [];
  };

  ## ── every output has a host directory backing it ──────────────────────────
  testEveryNixosConfigurationHasHostDir = {
    expr = lib.filter (n: !(builtins.elem (hostDirOf n) (hostDirs "nixos" ++ hostDirs "iso"))) (lib.attrNames nixos);
    expected = [];
  };

  testEveryDarwinConfigurationHasHostDir = {
    expr = missingFrom (lib.genAttrs (hostDirs "darwin") (_: null)) (lib.attrNames darwin);
    expected = [];
  };

  testEveryDroidConfigurationHasHostDir = {
    expr = missingFrom (lib.genAttrs (hostDirs "droid") (_: null)) (lib.attrNames droid);
    expected = [];
  };

  testHostNamesAreUniqueAcrossClasses = {
    expr = let
      all = lib.attrNames nixos ++ lib.attrNames darwin ++ lib.attrNames droid;
    in
      lib.length all == lib.length (lib.unique all);
    expected = true;
  };

  ## ── home-manager pairs with every system host (installers excluded) ───────
  testEverySystemHostHasHomeConfiguration = {
    expr = sorted (missingFrom home systemHosts);
    expected = [];
  };

  testEveryHomeConfigurationHasSystemHost = {
    expr = sorted (lib.subtractLists systemHosts (lib.attrNames home));
    expected = [];
  };

  ## ── deploy-rs ─────────────────────────────────────────────────────────────
  testDeploySystemNodesTargetExistingConfigurations = {
    expr = lib.filter (n: !(nixos ? ${configOfNode n} || droid ? ${configOfNode n})) systemNodes;
    expected = [];
  };

  testDeployHomeNodesTargetExistingHomeConfigurations = {
    expr = missingFrom home (map configOfNode homeNodes);
    expected = [];
  };

  testEveryDeployHomeNodeHasSystemNode = {
    expr = missingFrom nodes (map (lib.removeSuffix "-home") homeNodes);
    expected = [];
  };

  testDeployHomeNodesShareSystemNodeHostname = {
    expr = lib.filter (n: nodes.${n}.hostname != nodes.${lib.removeSuffix "-home" n}.hostname) homeNodes;
    expected = [];
  };

  testDeploySystemNodesDefineSystemProfile = {
    expr = lib.filter (n: !(nodes.${n}.profiles ? system)) systemNodes;
    expected = [];
  };

  testDeployHomeNodesDefineHomeProfile = {
    expr = lib.filter (n: !(nodes.${n}.profiles ? home)) homeNodes;
    expected = [];
  };

  testDeployNodesHaveHostname = {
    expr = lib.filter (n: (nodes.${n}.hostname or "") == "") nodeNames;
    expected = [];
  };

  testDeployVpsSystemNodesBuildRemotely = {
    expr = lib.filter (n: lib.hasPrefix "VPS" n && !(nodes.${n}.profiles.system.remoteBuild or false)) systemNodes;
    expected = [];
  };

  ## ── module outputs ────────────────────────────────────────────────────────
  testHomeManagerModulesExposeEveryModuleFile = {
    expr = let
      files = map (lib.removeSuffix ".nix") (lib.attrNames (builtins.readDir (self + "/modules/home")));
    in
      missingFrom self.homeManagerModules files;
    expected = [];
  };

  testDarwinModulesExposeEveryModuleFile = {
    expr = let
      files = map (lib.removeSuffix ".nix") (lib.attrNames (builtins.readDir (self + "/modules/hosts/darwin")));
    in
      missingFrom self.darwinModules files;
    expected = [];
  };
}
