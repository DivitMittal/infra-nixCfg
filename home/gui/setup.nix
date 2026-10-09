{
  lib,
  inputs,
  hostPlatform,
  ...
}: {
  imports =
    [(inputs.import-tree ./ide)]
    ++ [(inputs.import-tree ./music)]
    ++ [
      ./comms.nix
      ./docs.nix
      ./lan.nix
      ./notes.nix
      ./office.nix
      ./quant.nix
      ./video.nix
      ./vpn.nix
    ]
    ++ lib.lists.optionals hostPlatform.isDarwin [(inputs.import-tree ./darwin)]
    ++ lib.lists.optionals hostPlatform.isLinux [(inputs.import-tree ./linux)]
    ++ [
      inputs.term-nixCfg.homeManagerConfigurations.gui
    ];
}
