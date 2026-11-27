{pkgs, ...}: {
  programs.fish = {
    enable = true;
    package = pkgs.fish;

    loginShellInit = ''
      set -g fish_greeting
    '';

    interactiveShellInit = ''
      set -g fish_vi_force_cursor 1
      set -g fish_cursor_default block
      set -g fish_cursor_visual block
      set -g fish_cursor_insert line
      set -g fish_cursor_replace_one underscore
    '';

    shellAbbrs = {
      ".2" = {
        expansion = "../..";
        position = "anywhere";
      };
      ".3" = {
        expansion = "../../..";
        position = "anywhere";
      };
    };

    plugins = [
      ## Plugin manager (not longer needed)
      # {
      #   name = "fisher";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "jorgebucaran";
      #     repo = "fisher";
      #     rev = "4.4.5";
      #     hash = "sha256-VC8LMjwIvF6oG8ZVtFQvo2mGdyAzQyluAGBoK8N2/QM=";
      #   };
      # }
      {
        name = "autopair";
        src = pkgs.fetchFromGitHub {
          owner = "jorgebucaran";
          repo = "autopair.fish";
          rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
          hash = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
        };
      }
      {
        name = "puffer";
        src = pkgs.fetchFromGitHub {
          owner = "nickeb96";
          repo = "puffer-fish";
          rev = "83174b07de60078be79985ef6123d903329622b8";
          hash = "sha256-Dhx5+XRxJvlhdnFyimNxFyFiASrGU4ZwyefsDwtKnSg=";
        };
      }
      {
        name = "upto";
        src = pkgs.fetchFromGitHub {
          owner = "markcial";
          repo = "upto";
          rev = "631138eb3655d52f4cb8cfbc1a19b2d71dc70d7f";
          hash = "sha256-LuPY/q5d1kuEfFVqNrWCRIPvEsHhpravZ6BNN3SKo0c=";
        };
      }
      {
        name = "fc";
        src = pkgs.fetchFromGitHub {
          owner = "lengyijun";
          repo = "fc-fish";
          rev = "9457a9c47391ff712696bbef0e4a109de2a653d1";
          hash = "sha256-DQQofY5FPdy5kWctlKmi2SRTH7zL9ZpBdrdMx+iX+dA=";
        };
      }
      {
        name = "bass";
        src = pkgs.fetchFromGitHub {
          owner = "edc";
          repo = "bass";
          rev = "79b62958ecf4e87334f24d6743e5766475bcf4d0";
          hash = "sha256-3d/qL+hovNA4VMWZ0n1L+dSM1lcz7P5CQJyy+/8exTc=";
        };
      }
      {
        name = "osx-plugin";
        src = pkgs.fetchFromGitHub {
          owner = "oh-my-fish";
          repo = "plugin-osx";
          rev = "27039b251201ec2e70d8e8052cbc59fa0ac3b3cd";
          hash = "sha256-jSUIk3ewM6QnfoAtp16l96N1TlX6vR0d99dvEH53Xgw=";
        };
      }
    ];
  };
}
