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
            name = "R1 LAN (VLAN20)";
            cidrv4 = "192.168.2.0/24";
          };

          networks.ont = {
            name = "ONT/WAN Network (VLAN10)";
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
            # lan0: USB-gigabit link to S1 (port1) on the flat untagged LAN.
            # Bridged with lan1 into br-lan. MAC-pinned; see
            # hosts/openwrt/R1/modules/netnames.nix.
            interfaces.lan0 = {
              network = "home";
              type = "ethernet";
            };
            # wan0: USB-gigabit WAN uplink cabled directly to R0 (bypasses S1),
            # replacing the onboard 100M port on the WAN path. MAC-pinned.
            interfaces.wan0 = {
              network = "ont";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "r0";
                  interface = "lan";
                }
              ];
            };
            # eth0: onboard RTL8105e (100M), now an untagged LAN access port on
            # br-lan (repurposed from its former WAN role). Its PCI identity is
            # deterministic, so it keeps the kernel's stable eth0 name.
            interfaces.eth0 = {
              network = "home";
              type = "ethernet";
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
            hardware.info = "Airtel fiber ONT (optical-to-ethernet media converter)";
            interfaces.lan = {
              network = "internet";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "r0";
                  interface = "wan";
                }
              ];
            };
            interfaces.wan = {
              network = "internet";
              type = "wan";
            };
          };

          nodes.r0 = {
            name = "R0";
            deviceType = "router";
            hardware.info = "Airtel-provided router; DMZ forwards all WAN traffic to R1 (192.168.1.254)";
            interfaces.wan = {
              network = "internet";
              type = "ethernet";
            };
            interfaces.lan = {
              network = "ont";
              type = "ethernet";
            };
          };

          nodes.S1 = {
            name = "S1";
            deviceType = "switch";
            hardware.info = "TP-Link TL-SG105E managed switch; mgmt IP 192.168.2.2 (VLAN20, distinct from R1's 192.168.2.1)";
            # Uplink to R1 (lan0) on the flat untagged LAN — no VLAN tagging.
            # WAN is not trunked here; R0 cables directly into R1's wan0.
            interfaces.port1 = {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "router";
                  interface = "lan0";
                }
              ];
            };
            # VLAN20 access ports.
            interfaces.port2 = {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "L1";
                  interface = "eth0";
                }
              ];
            };
            interfaces.port3 = {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "L2";
                  interface = "eth0";
                }
              ];
            };
            interfaces.port4 = {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  node = "M1";
                  interface = "eth0";
                }
              ];
            };
            # port5: spare VLAN20 access port. The old VLAN10 WAN uplink from R0
            # is gone — R0 now cables directly into R1's onboard eth0.
            interfaces.port5 = {
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
            # Wired uplink to S1 (VLAN20, port2).
            interfaces.eth0 = {
              network = "home";
              type = "ethernet";
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

          # x86_64 desktop — dual-boot: NixOS (L2) | Windows 11 (L2-windows) — user: vanee
          nodes.L2 = {
            name = "L2";
            deviceType = "device";
            hardware.info = "NixOS desktop (x86_64) - dual-boot with Windows 11 (L2-windows) — user: vanee";
            # Wired uplink to S1 (VLAN20, port3).
            interfaces.eth0 = {
              network = "home";
              type = "ethernet";
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
            # Wired uplink to S1 (VLAN20, port4).
            interfaces.eth0 = {
              network = "home";
              type = "ethernet";
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
