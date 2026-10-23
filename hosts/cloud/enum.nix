_: {
  flake.cloudConfigurations = {
    VPS1 = import ./VPS1;
    VPS0 = import ./VPS0;
  };
}
