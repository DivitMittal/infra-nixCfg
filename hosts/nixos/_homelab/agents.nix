# Agent boxes (T3, T4): spare cores and RAM for running many API-backed AI
# agents (Claude Code, Codex, ...) so they don't load L1. The agent CLIs
# themselves come from ai-nixCfg via the home-manager profile; this is the
# host-side tuning that lets dozens of them run at once.
{config, ...}: {
  # Keep the user's systemd/tmux sessions (and the agents in them) running
  # after the SSH session that started them disconnects.
  users.users."${config.hostSpec.username}".linger = true;

  boot.kernel.sysctl = {
    # Each agent is a Node/Bun process with its own file watchers; the
    # defaults (8192 instances/user on some kernels) run out quickly.
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 1048576;
  };

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "-";
      item = "nofile";
      value = "1048576";
    }
  ];

  # Compressed RAM swap absorbs bursts; oomd kills the single runaway cgroup
  # instead of letting the whole box thrash.
  zramSwap.enable = true;
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
  };
}
