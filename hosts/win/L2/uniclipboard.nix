## UniClipboard on L2's Windows boot, joining L1 and T2's shared clipboard
## (home/tools/hid/uniclipboard.nix). `uniclip service` only manages systemd
## and launchd, so ./desk.nix gives the daemon a login task instead.
{
  self,
  config,
  pkgs,
  ...
}: let
  source = (pkgs.callPackage (self + "/pkgs/_sources/generated.nix") {}).uniclipboard-cli-x86_64-windows;
  package = pkgs.runCommand "uniclipboard-cli-windows-${source.version}" {nativeBuildInputs = [pkgs.unzip];} ''
    mkdir -p $out/bin
    unzip -q ${source.src} uniclip.exe uniclipd.exe -d $out/bin
  '';
  directory = "C:\\Users\\${config.win.user.name}\\AppData\\Local\\uniclipboard";
in {
  # Lands in %LOCALAPPDATA%\uniclipboard\bin, which nix-win adds to the user
  # PATH so `uniclip space join` works from any terminal.
  win.packages.uniclipboard.package = package;

  desk.daemons.UniClipboard = {
    executable = "${directory}\\bin\\uniclip.exe";
    arguments = "run";
    # `uniclip run` supervises uniclipd, which holds the network sockets.
    listener = "${directory}\\bin\\uniclipd.exe";
    # What `uniclip service start` sets on macOS and Linux.
    environment = {
      UNICLIPBOARD_ENV = "production";
      UC_CONSOLE_LOG = "off";
    };
    log = "${directory}\\daemon.log";
    processes = ["uniclip" "uniclipd"];
  };
}
