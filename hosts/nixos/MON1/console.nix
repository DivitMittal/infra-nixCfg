# The S100 reached tty1 with fb0 in FB_BLANK_POWERDOWN even though its lid was
# open, the panel was connected and agetty was healthy. Keep console login
# visible on this monitoring appliance without installing a desktop browser.
{pkgs, ...}: {
  systemd.services.mon1-console-display = {
    description = "Wake MON1's local login display";
    wantedBy = ["multi-user.target"];
    after = ["systemd-vconsole-setup.service" "getty@tty1.service"];
    unitConfig.ConditionPathExists = "/sys/class/graphics/fb0/blank";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.util-linux];
    script = ''
      printf '0' > /sys/class/graphics/fb0/blank
      setterm --term linux --blank 0 --powersave off --powerdown 0 < /dev/tty1 > /dev/tty1
    '';
  };
}
