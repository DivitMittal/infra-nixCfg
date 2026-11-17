{
  inputs,
  self,
  lib,
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
            name = "R0 network (GN XPON ONT/router)";
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

          # One box: a GN XPON ONT with a built-in router (fiber in,
          # Ethernet/Wi-Fi out).
          nodes.r0 = {
            name = "R0";
            deviceType = "router";
            hardware.info = "GN XPON ONT/router (ISP-provided, fiber in) in router mode (192.168.1.1), DMZ-forwarding to the T640 router's static WAN (192.168.1.254). Later option: bridge mode, passing PPPoE through for T640 to dial itself (`nix run .#t640-router-pppoe`) — see hosts/README.md. Also keeps its own Wi-Fi AP, which L1 currently uses (unmanaged by this flake)";
            interfaces.wan = {
              network = "internet";
              type = "wan";
            };
            interfaces.lan = {
              network = "ont";
              type = "ethernet";
            };
            # R0's own Wi-Fi AP (L1 currently associates here).
            interfaces.wlan = {
              network = "ont";
              type = "wifi";
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
                  node = "ASL1";
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
            # On R0's own Wi-Fi (the ISP router's network, outside the home
            # LAN), not wired to S1.
            interfaces.en0 = {
              network = "ont";
              type = "wifi";
              physicalConnections = [
                {
                  node = "r0";
                  interface = "wlan";
                }
              ];
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
            # Wired into S1 (port2); S1 declares the edge from its side.
            interfaces.eth0 = {
              network = "home";
              type = "ethernet";
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

          # L2 (NixOS desktop, dual-boot with L2-windows) registers itself
          # from hosts/nixos/L2/topology.nix.

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
        # Pass the nixosConfigurations so topology can discover them. Only
        # those that import the nix-topology module: it reads every passed
        # config's `options.topology`, and classes without it (netboot's
        # t1-netboot, a RAM-only PXE image) abort the whole build.
        {
          nixosConfigurations =
            lib.filterAttrs (_: cfg: cfg.options ? topology) self.nixosConfigurations;
        }
      ];
    };
  };
}
