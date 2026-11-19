# DASH management status

Last checked: 2026-11-20. This is separate from BIOS setting enforcement and
from the NixOS SSH service.

## Observed on the fleet

- T1 and T2's current kernel logs both report `r8169 ... DASH enabled`.
- TCP 623 and 664 do not accept connections on T1's host address or T2's
  current DHCP address. An alternative controller address has not been verified.
- T3 is reachable again at its OS address `192.168.2.8`. Existing boot logs
  report DASH enabled. Cached PCI identity is `10ec:8168`, revision `0e`,
  with the stock `r8169` driver; this does not identify the controller IP.
- The parent reports all three t640s online for 10 hours without outages on
  2026-11-20. No new firmware-query safety claim follows from that uptime.
- No management account has been provisioned by this repository, no DASH
  credentials have been stored, and no authenticated inventory or power
  operation has succeeded. The system is not yet remotely manageable via DASH.

Reproduce the driver check without querying firmware methods:

```sh
journalctl -b -k | grep -i DASH
```

A driver message establishes hardware enablement only; a failed TCP connection
to the OS address does not establish the controller's provisioning state.

## HP's documented capabilities and next steps

HP's [t640/t740 DASH guide](https://h10032.www1.hp.com/ctg/Manual/c06593878.pdf)
describes controller provisioning, management accounts and the Realtek console.
Its port table specifies HTTP WS-Man on TCP 623 and HTTPS on TCP 664. The
supported-profile table includes power state, inventory and boot control, but
does not list KVM or media redirection for these thin clients. Do not promise
remote screen access or arbitrary BIOS configuration from DASH enablement.

HP documents Windows and associated Realtek driver/agent requirements and says
ThinPro is unsupported for this workflow. A Linux provisioning backend on this
hardware remains unverified. Out-of-band transport support and the software
needed to provision it must be established separately.

Next: identify the controller's network configuration and supported provisioning
tool on T3, configure a management account with its credential in agenix, then
verify authenticated inventory before attempting a power action. Preserve T1's
router availability while testing. Any NIC firmware flashing or vendor BIOS
setting writes still need the owner's explicit approval.

## Linux tooling and implementation (2026-11-20)

AMD's [DASH CLI v9 release notes](https://www.amd.com/content/dam/amd/en/documents/support/downloads/dash-cli-releasenotes.pdf)
list Ubuntu 24.04 amd64 and Fedora 43 packages. This is a supported Linux
**management client**, not proof of Linux local provisioning on the t640.
AMD's [APC release notes](https://www.amd.com/content/dam/amd/en/documents/support/downloads/apc-release-notes.pdf)
document Windows provisioning and a Realtek-specific `DASHConfigRT.exe`
configuration workflow. Compatibility with this fleet remains untested.
No AMD/HP binary has been redistributed or disassembled for this follow-up.

The upstream [realtek-realmanage project](https://github.com/88plug/realtek-realmanage)
also provides Linux provisioning and controller network queries. Its driver
requirements list vendor `r8125`/`r8126`/`r8127` drivers and a private ioctl,
which stock `r8169` does not expose. The project's primary target is RTL8125BP;
its support claims do not verify this t640's `8168` device. Do not replace the
fleet NIC driver or run its activation daemon as a discovery shortcut.
Remote WS-Man clients and local controller provisioning are separate paths.

`pkgs/custom/homelab-dash-probe/` supplies a reproducible Python-only discovery
client. It sends exactly one unauthenticated WS-Man Identify request to the
literal IP and selected port, bounds the response and timeout, validates TLS
with the system CA set, does not follow redirects, and emits only HTTP status,
identity-presence and error classes. It never emits the response, usernames,
MACs or product identifiers. HTTP 401, closed ports and even a successful
Identify response all leave `provisioning` as `unknown`. Its six offline
fixture tests cover classification, redaction, malformed XML, request shape,
response bounds and transport errors. The package exposes those fixtures as
`passthru.tests.fixtures`. It has no credential or power-action path.

```sh
# Offline fixture validation; no network access:
python3 -B -m unittest discover -s pkgs/custom/homelab-dash-probe -v
# Package build on a coordinated Linux builder:
nix build --no-link .#nixosConfigurations.T3.pkgs.custom.homelab-dash-probe
# Only after parent coordination for this exact vendor network query:
homelab-dash-probe 192.168.2.8 --port 623
homelab-dash-probe 192.168.2.8 --port 664
```

The client has not been run against a live controller. A private/self-signed
certificate will fail validation; there is no insecure-TLS switch. A known
management CA can be provided through the standard `SSL_CERT_FILE` mechanism.
An unsuccessful probe of `.8` would still leave alternate controller addressing
and provisioning unresolved. No password guesses, subnet scans, DHCP changes,
NIC firmware operations, power tests or reboots were performed.

**Next parent coordination:** approve those two bounded unauthenticated
Identify requests to T3's OS address, then correlate any result with existing
router DHCP/neighbor evidence without committing identifiers. If a separate
controller address cannot be established that way, obtain the controller
network/provisioning screen through an explicitly approved console session.
Use an authenticated inventory request only after the actual account and
trusted endpoint are known, keeping credentials in agenix runtime files.
