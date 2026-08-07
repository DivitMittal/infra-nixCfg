{
  inputs,
  self,
  ...
}: {
  imports = [
    inputs.nix-topology.flakeModule
  ];

  perSystem = _: {
    topology = {
      modules = [
        {
          networks.home = {
            name = "R1 LAN";
            cidrv4 = "192.168.2.0/24";
          };

          networks.ont = {
            name = "ONT Network";
            cidrv4 = "192.168.1.0/24";
          };

          networks.wsl = {
            name = "WSL Network";
            cidrv4 = "172.16.0.0/12";
          };

          networks.mobile = {
            name = "Android USB Tethering";
            cidrv4 = "10.0.0.0/8";
          };

          networks.tailnet = {
            name = "Tailscale Tailnet";
            cidrv4 = "100.64.0.0/10";
          };

          networks.internet = {
            name = "Internet";
            cidrv4 = "0.0.0.0/0";
          };

          # Lima/Colima virtual bridge networks (one per host Mac)
          networks.colima-x86 = {
            name = "Colima x86_64 Network";
            cidrv4 = "192.168.5.0/24";
          };

          networks.colima-arm = {
            name = "Colima ARM Network";
            cidrv4 = "192.168.106.0/24";
          };

          nodes.router = {
            name = "R1";
            deviceType = "router";
            hardware.info = "Lenovo S100, Intel Atom, 2 GiB RAM, x86_64 OpenWrt; 8 GiB overlay + 290 GiB internal storage; 500 GB USB WD exFAT NAS via ksmbd";
            interfaces.eth1 = {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "tp-link-switch";
                  interface = "uplink";
                }
              ];
            };
            interfaces.eth2 = {
              network = "ont";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "ont";
                  interface = "lan";
                }
              ];
            };
            interfaces.tailscale0 = {
              network = "tailnet";
              type = "virtual";
              virtual = true;
            };
          };

          nodes.ont = {
            name = "ONT";
            deviceType = "router";
            hardware.info = "DMZ host at 192.168.1.1";
            interfaces.lan = {
              network = "ont";
              type = "ethernet";
            };
            interfaces.wan = {
              network = "internet";
              type = "wan";
            };
          };

          nodes.tp-link-switch = {
            name = "TP-Link Gigabit Switch";
            deviceType = "switch";
            hardware.info = "R1 DHCP clients and static-IP LAN clients";
            interfaces.uplink = {
              network = "home";
              type = "ethernet";
            };
            interfaces.lan1 = {
              network = "home";
              type = "ethernet";
            };
          };

          # x86_64 MacBook — triple-boot: macOS (L1 / nix-darwin) | NixOS T2 | Windows 11
          nodes.L1 = {
            name = "L1";
            deviceType = "device";
            hardware.info = "macOS nix-darwin (x86_64) - triple-boot with T2 NixOS & Windows 11";
            interfaces.en0 = {
              network = "home";
              type = "wifi";
            };
            # Virtual bridge for the Colima x86_64 VM
            interfaces.col0 = {
              network = "colima-x86";
              type = "virtual";
              virtual = true;
            };
          };

          # Apple Silicon MacBook — dual-boot: macOS (AS / nix-darwin) | NixOS Asahi
          nodes.ASL1 = {
            name = "ASL1";
            deviceType = "device";
            hardware.info = "macOS nix-darwin (aarch64) - dual-boot with Asahi NixOS";
            interfaces.en0 = {
              network = "home";
              type = "wifi";
              physicalConnections = [
                {
                  node = "router";
                  interface = "wlan";
                }
              ];
            };
            # Virtual bridge for the Colima ARM VM
            interfaces.col0 = {
              network = "colima-arm";
              type = "virtual";
              virtual = true;
            };
          };

          # Windows 11 boot on the x86_64 MacBook (triple-boot partner of L1 & T2) — user: div
          # Packages + system settings: https://github.com/DivitMittal/playbooks-4-windows (Ansible)
          # TTY dotfiles (starship, fastfetch, git attrs): WSL home-manager → /mnt/c/Users/div/
          nodes.windows-host = {
            name = "Windows Host (L1)";
            deviceType = "device";
            hardware.info = "Windows 11 - triple-boot with L1 (macOS) & T2 (NixOS) — user: div | pkgs+settings: Ansible | TTY dotfiles: WSL home-manager";
            interfaces.wlan0 = {
              network = "home";
              type = "wifi";
              physicalConnections = [
                {
                  node = "router";
                  interface = "wlan";
                }
              ];
            };
            interfaces.wsl0 = {
              network = "wsl";
              type = "virtual";
              virtual = true;
            };
          };

          # Windows 11 boot on the x86_64 machine (dual-boot partner of L2 NixOS) — user: vanee
          # Managed by https://github.com/DivitMittal/playbooks-4-windows (Ansible IaC)
          nodes.L2-windows = {
            name = "Windows (L2)";
            deviceType = "device";
            hardware.info = "Windows 11 (Ansible IaC) - dual-boot with L2 NixOS on x86_64 hardware — user: vanee";
            interfaces.wlan0 = {
              network = "home";
              type = "wifi";
              physicalConnections = [
                {
                  node = "router";
                  interface = "wlan";
                }
              ];
            };
          };

          nodes.M1 = {
            name = "M1";
            deviceType = "device";
            hardware.info = "Android - nix-on-droid (aarch64 MediaTek)";
            interfaces.wlan0 = {
              network = "home";
              type = "wifi";
            };
          };
        }
        # Pass the nixosConfigurations so topology can discover them
        {
          inherit (self) nixosConfigurations;
        }
      ];
    };
  };
}
