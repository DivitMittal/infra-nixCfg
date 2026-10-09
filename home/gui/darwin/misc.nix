{
  pkgs,
  lib,
  hostPlatform,
  ...
}: {
  home.packages = lib.attrsets.attrValues (
    {
      inherit
        (pkgs.brewCasks)
        pearcleaner # macOS all-in-one cleaner
        hot # CPU temperature monitor for menubar
        stats # macOS system monitor in menubar (CPU/GPU/mem/disk/sensors)
        hiddenbar # hide/show menubar icons
        linearmouse # mouse/trackpad customization
        music-decoy # prevent macOS Music from auto-launching on media keys
        finetune # audio fine-tuning and volume control
        #gswitch # MUX switcher (using pmset instead)
        #bluesnooze # turns bluetooth off when asleep
        #aldente # Battery Management
        #licecap # Screen GIF capture for showcasing
        #keycastr # Keystroke visualizer
        #brilliant # Screen Anotation Tool
        ;
      inherit
        (pkgs.customDarwin)
        Spaceman-bin # spaces in menubar for macOS (ruittenb fork)
        menubar-dock # macOS dock in menubar
        LiveWallpaperMacOS-bin # Live wallpaper for macOS
        #MultiSoundChanger-bin # aggregate-output volume control in menubar
        #Iris-bin # Webcam mirror
        #LosslessSwitcher-bin # Lossless audio toggle in menubar
        ;
    }
    // lib.optionalAttrs hostPlatform.isx86_64 {
      VoltageShift = pkgs.customDarwin.VoltageShift; # Intel-only undervolting CLI
      smc = pkgs.customDarwin.smc; # Intel-only SMC fan/temp reading CLI
    }
  );
}
