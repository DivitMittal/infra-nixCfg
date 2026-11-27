# M1 system keyboard

With Unexpected Keyboard (`juloo.keyboard2`) installed and the ADB shell granted
root through KernelSU, run from the repository root:

```sh
nix run .#m1-keyboard -- --serial SERIAL plan
nix run .#m1-keyboard -- --serial SERIAL apply
```

`plan` is read-only and returns exit code 3 if changes are pending. `apply`
manages the standalone app's layout using the same [TLTR XML](../keyboard/layout.xml)
as B1 and makes it the default input method for Android's owner user. It
updates and checks both the settings screen's preferences and the live input
method's direct-boot preferences. It does not modify Termux Launcher's
embedded layout or disable M1's other input methods.

## Kernel module management

M1's planned declarative root-module management should target ReSukiSU/KernelSU,
not B1's Magisk wrapper. The shared module format, `/data/adb/modules` layout,
and disable/remove markers are compatible, but installation and activation are
not interchangeable. M1 should use `ksud module install` (or the manager-supported
equivalent exposed by the installed ReSukiSU build), while B1 continues to use
`magisk --install-module`.

`m1-ksu` implements this boundary. Declare module IDs, ZIP paths, and enabled
state in a JSON manifest, then run `nix run .#m1-ksu -- --manifest manifest.json
--serial SERIAL plan`. Planning exits 3 for a missing module, hash drift, or
enabled-state drift. Apply uses `ksud module install`, then `enable` or
`disable`, and records the ZIP SHA-256. It neither removes undeclared modules
nor reboots M1. A module that changes
`system/` also needs the appropriate KernelSU metamodule before its files can be
mounted. Modules should remain staged until an explicit reboot unless the selected
module and installed ReSukiSU version both support hot installation. Do not treat
a Magisk module ZIP as automatically installable or behavior-compatible on M1.
