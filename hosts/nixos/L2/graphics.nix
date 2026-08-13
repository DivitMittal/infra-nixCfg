# AMD integrated graphics (Vega/RDNA, Ryzen APU) for the Flex 5. No prior GPU
# driver config existed on this host — required baseline for Proton/Steam
# (32-bit graphics) on top of whatever mesa provides by default.
{
  boot.initrd.kernelModules = ["amdgpu"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
