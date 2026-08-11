{
  hostPlatform,
  lib,
  ...
}: {
  ## Objective-See firewall + persistence/malware scanner
  homebrew.casks = lib.optionals hostPlatform.isDarwin ["lulu" "knockknock"];
}
