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
