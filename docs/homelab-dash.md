# DASH management status

Last checked: 2026-11-19. This is separate from BIOS setting enforcement and
from the NixOS SSH service.

## Observed on the fleet

- T1 and T2's current kernel logs both report `r8169 ... DASH enabled`.
- TCP 623 and 664 do not accept connections on T1's host address or T2's
  current DHCP address. An alternative controller address has not been verified.
- T3 is currently unreachable through its OS network, so its current DASH
  state has not been inspected.
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
