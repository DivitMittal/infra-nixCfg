{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bash
    btop
    curl
    fd
    git
    gnugrep
    jq
    ripgrep
    vim
    wget
  ];
}
