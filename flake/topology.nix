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

          # R1 (Lenovo S100) used to be manually declared here as this
          # flake's router node. It is no longer a router — T1
          # (hosts/nixos/T1) has taken over that role entirely, and
          # registers its own self-topology node under this same "router"
          # id (see hosts/nixos/T1/topology.nix's `topology.id` override
          # and the nixosConfigurations pass-through at the bottom of this
          # file). The S100 itself is now MON1 (hosts/nixos/MON1), the
          # monitoring node; its old declarative OpenWrt config
          # (hosts/openwrt/R1) is kept in place as historical/rollback
          # reference, no longer deployed.

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
            hardware.info = "Airtel-provided router, reconfigured into bridge mode: passes the ISP's PPPoE session(s) straight through to T1's WAN NIC (T1 terminates PPPoE itself). Fallback: DMZ-forwards a static IP to T1's WAN (192.168.1.254) if PPPoE passthrough proves unreliable — see hosts/README.md. Also independently keeps broadcasting its own legacy 2.4GHz Wi-Fi AP for older/IoT devices (unmanaged by this flake)";
            interfaces.wan = {
              network = "internet";
              type = "ethernet";
            };
            interfaces.lan = {
              network = "ont";
              type = "ethernet";
            };
          };

          # Unmanaged switch hanging off S1's last free port, carrying the
          # home-lab nodes S1 has no room for. Cabling is assumed; adjust to
          # match reality. The Lenovo S100 (formerly R1) is now MON1 and
          # registers its own node from hosts/nixos/MON1/topology.nix.
          nodes.SW2 = let
            downlink = node: {
              network = "home";
              type = "ethernet";
              physicalConnections = [
                {
                  inherit node;
                  interface = "lan0";
                }
              ];
            };
          in {
            name = "SW2";
            deviceType = "switch";
            hardware.info = "Unmanaged switch (not monitorable; visible only through probes of the hosts behind it)";
            interfaces = {
              uplink = {
                network = "home";
                type = "ethernet";
                physicalConnections = [
                  {
                    node = "S1";
                    interface = "port5";
                  }
                ];
              };
              port2 = downlink "T3";
              port3 = downlink "T4";
              port4 = downlink "MON1";
            };
          };

          nodes.S1 = {
            name = "S1";
            deviceType = "switch";
            hardware.info = "TP-Link TL-SG105E managed switch; mgmt IP 192.168.2.2 (VLAN20; the router's LAN gateway IP moved from R1's old 192.168.2.1 to T1/T640 — exact value TBD, not yet configured)";
            # Uplink to T1 (lan0, on its router VM) on the flat untagged LAN
            # — no VLAN tagging. WAN is not trunked here; R0 cables directly
            # into T1's wan.
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
            # port5: uplink to the unmanaged SW2 (declared from SW2's side).
            # The old VLAN10 WAN uplink from R0 is gone — R0 now cables
            # directly into T1's wan.
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
