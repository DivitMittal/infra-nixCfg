# Homelab SNMP and L1 link investigation

Observed 2026-11-20 from isolated branch based on master 10687584. No live
configuration was changed, no deployment/build was performed, and no SNMP
community was guessed. S1 login used its existing encrypted admin secret,
decrypted in process memory; only read pages were fetched after login.

## L1 link evidence

- `/sbin/ifconfig en23`: autoselect, 100baseTX full duplex, 192.168.2.4/24,
  `networksetup -getMedia en23` agrees.
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

- MON1 SSH: enp1s0 reports 100 Mb/s. Router ARP confirms the device
  associations; per-device inventory identifiers belong in the private repo.
- Twelve small ping requests to each of MON1, T3, T2 and router all succeeded;
  no bad packet counters increased during these samples. Background traffic
  makes good-packet deltas insufficient to certify each physical port mapping.

User subsequently confirmed the physical path L1 → S1 → T1 → USB adapter →
R0. L1 is directly attached to S1, not S2, and its current route through T1 is
intended. Only S1 port 1 currently reports 100 Mb/s, making it the candidate
L1 port, but the physical socket number still needs explicit confirmation.
MON1's physical switch path has not been confirmed. The repository's old
mapping (T3 on 1, MON1 on 3) is unverified; do not rewrite topology from
traffic deltas or assume MON1 is directly attached.

**Physical cause is not yet established.** The adapter and USB bus support
1 Gb/s operation. A damaged/missing cable pair, a 100-only peer port, or a
PHY/driver negotiation problem remains possible. A gigabit uplink on an
intermediate switch does not prove that L1's access port is gigabit.
Next confirm the numbered S1 socket holding L1's cable without unplugging
anything. During a user-coordinated brief interruption of L1's active internet,
replace only that cable with a known-good four-pair Cat5e/6 cable in the same
socket. Recheck en23 media and S1 actual speed. If it becomes 1000Full, the
original cable/connector path is implicated. If it remains 100Full, next test
that known-good cable on a confirmed unused S1 port, with parent coordination;
do not move any T1 or other active host cable. A port-dependent result
implicates the original switch port; 100 Mb/s on both leaves the adapter/PHY/
driver to isolate with a known-good adapter later.
Do not force 1000, change routes, reset counters, or disturb T1 to test this.

## R0 credential and capability gate

User subsequently identified R0 as GX XPON Titanium2122A and confirmed that
its actual SNMP UI offers v3. Firmware and algorithm dropdowns remain to be
confirmed. R0 at 192.168.1.1 answers HTTP with a redirect to /cgi-bin/login.asp; its
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
snmp_exporter `--dry-run --config.file /run/agenix/r0-snmp` before coordinated activation; do not
paste its contents or debug logs into CI. The pinned nixpkgs exporter is
0.30.1; its [tagged source](https://github.com/prometheus/snmp_exporter/blob/v0.30.1/main.go)
defines `--dry-run` and exits after config validation, before starting HTTP.
The exporter is not currently installed on MON1, so this is source-verified,
not a claim of a live binary test. Exporter listens 127.0.0.1:9116 and
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
file 0600). The wrapper rejects any group/other permission bits using the
explicit Nix coreutils GNU stat binary, including through symlinks. Obtain an encrypted client configuration separately; never put
plaintext defAuthPassphrase/defPrivPassphrase or defCommunity in Nix config.
Set defVersion, defSecurityName, defSecurityLevel, defAuthType, defPrivType and
passphrases to the verified v3 settings. No default credentials are supplied.

Heavy evaluation belongs to GitHub Actions eval.yml for MON1 and L1. Local
verification is formatting, syntax parsing and diff review only. Actual scrape
verification requires the credential gate and parent-coordinated deployment.

## Exact parent questions

Cable/port confirmation: “Which numbered S1 socket holds L1's cable? Please
check without unplugging it. Once confirmed, can we schedule a brief
interruption of L1's internet to replace only that cable with a known-good
four-pair Cat5e/6 cable in the same port? We will compare L1 and S1 link
speeds before considering a confirmed unused switch port.”

R0 secure action: “Please open R0's admin UI locally and provide its model,
firmware version, and SNMP page with all communities/passwords redacted.
Report whether SNMP is enabled and which versions/security modes are offered.
If existing read-only credentials are available, save them directly into the
private agenix secrets workflow; do not paste them into chat or a GitHub PR.”

## Titanium2122A: settings for the actual UI

The [GX datasheet](https://gxgroup.s3.ap-south-1.amazonaws.com/images/products-dataSheet/7e68b6260bef6eebb592e99b13aa3bc3.pdf)
does not document SNMP configuration fields or algorithms. User confirmation
of the UI establishes v3 availability, not particular authentication/privacy
algorithms. Before applying, supply the redacted field labels and dropdown
choices so the following values can be mapped exactly:

| Setting, if present              | Value                                                                                                                                                    |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SNMP version                     | v3 only; disable v1/v2c if independently selectable                                                                                                      |
| User/security name               | dedicated `mon1_ro` (a separate `l1_ro` if supported)                                                                                                    |
| Access permission                | read-only; no write view/access                                                                                                                          |
| Security level                   | authPriv (authentication plus privacy)                                                                                                                   |
| Authentication                   | SHA-256 if offered; otherwise SHA (SHA-1), explicitly select                                                                                             |
| Privacy                          | strongest AES mode offered and interoperable with both clients; AES-128 is the standard common baseline; do not assume AES-192/256 dialect compatibility |
| Authentication/privacy passwords | two distinct random passwords, generated and saved privately; obey the actual UI length/character limits, at least 8 characters, preferably 20+          |
| Allowed manager/source           | 192.168.1.254/32, or 192.168.1.254 with mask 255.255.255.255 if separate fields                                                                          |
| WAN/Internet SNMP access         | disabled; no port forwarding or UPnP mapping                                                                                                             |
| Traps/informs                    | disabled; polling does not need a trap receiver                                                                                                          |
| Engine ID/context                | retain device-generated engine ID; default/empty context unless UI requires otherwise                                                                    |

Do not change the router's other remote-management settings. If v3 cannot be
restricted to read-only access, or the only privacy choice is DES, report the
actual fields before applying. Do not silently downgrade to noAuthNoPriv.

**Source ACL evidence:** safe HTTP requests from L1 and MON1 each produced
conntrack entries on the router with original source 192.168.2.4 or .5 and
reply destination 192.168.1.254. eth1 is 192.168.1.254/24; nft srcnat dispatches
eth1 to the IPv4 fullcone NAT chain. This establishes the current translated
source for both clients. UDP/161 must still be confirmed with the first
credentialed GET after UI setup. An R0 ACL allowing .254 consequently trusts
traffic NATed through this router, not uniquely those two LAN hosts; dedicated
SNMPv3 credentials retain authentication scope. Do not add a new R0 route or
change NAT merely to configure monitoring.

**Private capture:** generate the two passwords in the user's password manager
and enter them locally in R0's UI. After field/algorithm confirmation, populate
separate exporter and client configurations through the private secrets repo's
agenix editor workflow, never a shell command containing passwords. Encrypt
for the intended host identities before committing ciphertext. Keep any editor
swap/backup files outside public repositories and remove temporary plaintext.
The public module receives only the ciphertext path; the client receives a
runtime snmp.conf with mode 0600. Do not ask the user to paste secrets or an
unredacted SNMP page into chat. Record the selected nonsecret algorithms and
firmware so client settings can match them exactly.
