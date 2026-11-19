# Homelab SNMP and L1 link investigation

Observed 2026-11-20 from isolated branch based on master 10687584. No live
configuration was changed, no deployment/build was performed, and no SNMP
community was guessed. S1 login used its existing encrypted admin secret,
decrypted in process memory; only read pages were fetched after login.

## L1 link evidence

- `/sbin/ifconfig en23`: autoselect, 100baseTX full duplex, 192.168.2.4/24,
  MAC 9c:69:d3:7f:90:de. `networksetup -getMedia en23` agrees.
- `/sbin/route -n get default`: gateway 192.168.2.1 on en23. R0
  192.168.1.1 also routes through that gateway. The previous no-gateway/Wi-Fi
  handoff is stale; preserve the active Ethernet internet route.
- `system_profiler SPEthernetDataType`: ASIX AX88179B, USB VID 0x0b95,
  PID 0x1790, USB link up to 5 Gb/s, Apple CDC NCM driver.
  `networksetup -listValidMedia en23` includes 1000baseT.
- ASIX specifies the AX88179B as a **10/100/1000** PHY. macOS also lists
  2500/5000 media and a 5 Gb/s maximum; these generic driver reports are not
  evidence that this particular adapter has a 5 Gb/s Ethernet PHY.
  [ASIX specification](https://www.asix.com.tw/en/product/USBEthernet/Super-Speed_USB_Ethernet/AX88179B)
- S1 authenticated SystemInfoRpm.htm: TL-SG105E 5.0, firmware
  1.0.0 Build 20250710 Rel.71066, management 192.168.2.2.
- S1 PortSettingRpm.htm: all five ports enabled, speed auto, flow control
  off. Actual port 1 = 100Full; ports 2–5 = 1000Full.
- S1 PortStatisticsRpm.htm snapshot (TxGood, TxBad, RxGood, RxBad):

  | Port |   TxGood | TxBad |   RxGood | RxBad |
  | ---- | -------: | ----: | -------: | ----: |
  | 1    | 70509981 |     0 | 28497711 |     4 |
  | 2    | 30595295 |     0 | 72715729 |     0 |
  | 3    | 22782622 |     0 |  2294495 |     2 |
  | 4    | 16589245 |     0 | 38696694 |     0 |
  | 5    | 21991534 |     0 | 11454387 |     0 |

- MON1 SSH: enp1s0 reports 100 Mb/s; MAC 50:af:73:11:7f:bd.
  Router ARP confirms L1 and MON1 MACs and R0 MAC bc:62:d2:11:77:38.
- Twelve small ping requests to each of MON1, T3, T2 and router all succeeded;
  no bad packet counters increased during these samples. Background traffic
  makes good-packet deltas insufficient to certify each physical port mapping.

The repository's old port mapping (T3 on 1, MON1 on 3) does not agree with
these link observations if those hosts are still directly attached. Treat
it as unverified rather than rewriting topology based on inference.

**Physical cause is not yet established.** The adapter and USB bus support
1 Gb/s operation. A damaged/missing cable pair, a 100-only peer port, or a
PHY/driver negotiation problem remains possible. A gigabit uplink on an
intermediate switch does not prove that L1's access port is gigabit.
Next obtain the physical L1 → peer → S1 cable/port trace and peer model.
Then, during a user-coordinated interruption of L1's active internet, test a
known-good four-pair Cat5e/6 cable and known-good gigabit peer port separately.
Do not force 1000, change routes, reset counters, or disturb T1 to test this.

## R0 credential and capability gate

R0 at 192.168.1.1 answers HTTP with a redirect to /cgi-bin/login.asp; its
unauthenticated page title is only Login. This does not establish model,
firmware, supported SNMP versions, or whether SNMP is enabled. The checked
network secret directory contains S1/T640 and WireGuard secrets, no R0 secret.
Do not reuse S1 credentials against R0 or probe default communities.

Parent needs the exact R0 model/firmware and an authenticated **read-only**
view of its SNMP configuration. Prefer SNMPv3 authPriv, a dedicated read-only
principal, and a source ACL for MON1 192.168.2.5 and L1 192.168.2.4. Verify
which source R0 actually sees after routing/NAT before configuring an ACL.
No WAN exposure, public community, write principal, trap receiver, or inbound
firewall opening is required. If firmware only supports v2c, explicitly agree
the restricted-LAN fallback and obtain its existing read-only community securely.
Enabling/changing R0 SNMP is a parent-coordinated live action.

## MON1 implementation and activation

`hosts/nixos/MON1/snmp.nix` auto-imports independently of monitoring.nix.
`homelab.r0Snmp.encryptedConfig` defaults to null, so no polling/service or
new dashboard is enabled until credentials/capabilities are verified.
Set it to an agenix ciphertext path from the private secrets input, encrypted
for MON1's age identity. The decrypted complete exporter YAML must define
`auths.r0` and `modules.r0`. Generate the module using the upstream generator
for the supported system/IF-MIB OIDs; include ifHCInOctets, ifHCOutOctets,
ifInErrors and ifOutErrors for all dashboard panels. Confirm HC counters exist
on this firmware; do not assume vendor optical metrics or invent OIDs.

The module decrypts root-only mode 0400; systemd LoadCredential gives the
exporter's service identity a runtime copy. Build-time config checking is
deliberately disabled because the upstream NixOS checker copies runtime string
paths into the Nix store. Validate the decrypted file on MON1 with the installed
snmp_exporter `--dry-run --config.file` before coordinated activation; do not
paste its contents or debug logs into CI. Exporter listens 127.0.0.1:9116 and
Prometheus polls only 192.168.1.1 once/minute. Grafana uses the existing
Prometheus datasource and provisions availability, traffic and errors panels.

[Exporter auth/module format](https://github.com/prometheus/snmp_exporter/blob/main/README.md)
and [generator](https://github.com/prometheus/snmp_exporter/tree/main/generator).
No secret input or lockfile changes are included in this branch.

## L1 client

`hosts/darwin/L1/programs/snmp.nix` installs Net-SNMP and `r0-snmp-status`
for a future coordinated Darwin activation; **do not activate L1 for this task**.
The wrapper makes three bounded numeric-OID GETs for sysDescr/sysObjectID/
sysUpTime and takes credentials through a private snmp.conf, never command
arguments. Set R0_SNMP_CONFIG_DIR to an agenix-managed runtime directory,
or place the decrypted file at ~/.config/r0-snmp/snmp.conf (directory 0700,
file 0600). Obtain an encrypted client configuration separately; never put
plaintext defAuthPassphrase/defPrivPassphrase or defCommunity in Nix config.
Set defVersion, defSecurityName, defSecurityLevel, defAuthType, defPrivType and
passphrases to the verified v3 settings. No default credentials are supplied.

Heavy evaluation belongs to GitHub Actions eval.yml for MON1 and L1. Local
verification is formatting, syntax parsing and diff review only. Actual scrape
verification requires the credential gate and parent-coordinated deployment.
