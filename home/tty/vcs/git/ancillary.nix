{
  pkgs,
  config,
  lib,
  hostPlatform,
  ...
}: let
  clipboardCmd =
    if hostPlatform.isDarwin
    then "pbcopy"
    else if hostPlatform.isLinux
    then "${pkgs.wl-clipboard}/bin/wl-copy"
    else "cat >/dev/null";
in {
  home.packages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      transcrypt
      git-filter-repo
      ;

    gen-gitignore = pkgs.writeShellScriptBin "gen-gitignore" ''
      if [ $# -eq 0 ]; then
        echo "Usage: gen-gitignore <template1> [template2] ..." >&2
        echo "Example: gen-gitignore python node vim" >&2
        exit 1
      fi

      # Join arguments with commas for gitignore.io API
      templates=$(IFS=,; echo "$*")
      ${pkgs.curl}/bin/curl -sL "https://www.gitignore.io/api/$templates"
    '';

    merge-flake-lock-prs = pkgs.writeShellApplication {
      name = "merge-flake-lock-prs";
      runtimeInputs = with pkgs; [gh jq];
      text = ''
        # Sweep flake.lock update PRs across one or more GitHub owners (users or
        # orgs): assign, approve, merge, and delete the source branch.
        #
        # These PRs are opened by the update-flake-lock action (see
        # .github/workflows/flake-lock-update.yml) and only ever touch flake.lock,
        # so they're safe to merge unattended. Matching the exact title AND a bot
        # author is what keeps the sweep safe — human PRs are never touched.
        #
        # Usage: merge-flake-lock-prs [--dry-run] [--assignee LOGIN] [OWNER...]

        PR_TITLE="flake.lock: Update"
        ASSIGNEE="DivitMittal"
        DRY_RUN=false
        OWNERS=()
        DEFAULT_OWNERS=(DivitMittal Qezta)

        while [ $# -gt 0 ]; do
          case "$1" in
          --dry-run)
            DRY_RUN=true
            shift
            ;;
          --assignee)
            [ $# -ge 2 ] || {
              echo "error: --assignee needs a value" >&2
              exit 1
            }
            ASSIGNEE="$2"
            shift 2
            ;;
          -h | --help)
            echo "Usage: merge-flake-lock-prs [--dry-run] [--assignee LOGIN] [OWNER...]"
            exit 0
            ;;
          -*)
            echo "error: unknown flag: $1" >&2
            exit 1
            ;;
          *)
            OWNERS+=("$1")
            shift
            ;;
          esac
        done

        [ ''${#OWNERS[@]} -gt 0 ] || OWNERS=("''${DEFAULT_OWNERS[@]}")

        gh auth status >/dev/null 2>&1 || {
          echo "error: gh is not authenticated (run: gh auth login)" >&2
          exit 1
        }

        # Run a command, or just print it when in dry-run mode.
        run() {
          if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] $*"
          else
            "$@"
          fi
        }

        processed=0
        failed=0

        for owner in "''${OWNERS[@]}"; do
          echo "==> Scanning owner: $owner"

          # Find open flake.lock PRs, then re-filter locally on exact title AND
          # bot author so a human PR can never slip through a loose search match.
          mapfile -t prs < <(
            gh search prs "$PR_TITLE" \
              --owner "$owner" --state open --match title \
              --json repository,number,title,author --limit 200 |
              jq -r --arg t "$PR_TITLE" \
                '.[] | select(.title == $t and .author.type == "Bot")
                     | "\(.repository.nameWithOwner)\t\(.number)"'
          )

          if [ ''${#prs[@]} -eq 0 ]; then
            echo "    (no matching flake.lock PRs)"
            continue
          fi

          for entry in "''${prs[@]}"; do
            repo="''${entry%%$'\t'*}"
            num="''${entry##*$'\t'}"
            echo "--- $repo #$num"

            if ! run gh pr edit "$num" --repo "$repo" --add-assignee "$ASSIGNEE" ||
              ! run gh pr review "$num" --repo "$repo" --approve ||
              ! run gh pr merge "$num" --repo "$repo" --merge --delete-branch; then
              echo "    FAILED on $repo #$num — left open for manual review" >&2
              failed=$((failed + 1))
              continue
            fi
            processed=$((processed + 1))
          done
        done

        echo
        echo "Done. processed=$processed failed=$failed"
        [ "$failed" -eq 0 ]
      '';
    };
  };

  programs.gh = {
    enable = true;
    package = pkgs.gh;
    extensions = lib.attrsets.attrValues {
      inherit
        (pkgs)
        ## Manage
        gh-f
        gh-notify
        gh-dash
        ## Contribution
        gh-eco
        gh-skyline
        gh-contribs # gh-cal
        ## Misc
        github-copilot-cli
        gh-screensaver
        gh-markdown-preview
        ;
    };

    gitCredentialHelper = {
      enable = true;
      hosts = ["https://github.com" "https://gist.github.com"];
    };
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      pager = "${config.home.sessionVariables.PAGER}";
      editor = "${config.home.sessionVariables.EDITOR}";
      aliases = {
        co = "pr checkout";
      };
    };
  };

  home.shellAliases.lg = "${pkgs.lazygit}/bin/lazygit";
  programs.lazygit = {
    enable = true;
    package = pkgs.lazygit;

    settings = {
      gui = {
        mouseEvents = true;

        border = "rounded";
        animateExplosion = true;

        nerdFontsVersion = "3";
        showFileIcons = true;

        showFileTree = true;
        showRandomTip = true;
        showBottomLine = true;
      };

      git = {
        autoFetch = true;
        fetchAll = true;
        autoRefresh = true;
        parseEmoji = true;
        pagers = [
          {
            colorArg = "always";
            pager = "${pkgs.delta}/bin/delta --paging=never";
          }
        ];
      };

      # What to do when opening Lazygit outside of a git repo.
      # - 'prompt': (default) ask whether to initialize a new repo or open in the most recent repo
      # - 'create': initialize a new repo
      # - 'skip': open most recent repo
      # - 'quit': exit Lazygit
      notARepository = "skip";

      update.method = "never";

      os = {
        shell = "${pkgs.bash}/bin/bash";
        shellArg = "-c";
      };

      keybinding = {
        universal = {
          prevItem = "<up>";
          nextItem = "<down>";
          prevItem-alt = "";
          nextItem-alt = "";

          scrollLeft = "<left>";
          scrollRight = "<right>";

          gotoTop = "g";
          gotoBottom = "G";

          prevBlock = "";
          nextBlock = "";
          prevBlock-alt = "";
          nextBlock-alt = "";
          nextBlock-alt2 = "<tab>";
          prevBlock-alt2 = "<backtab>";

          scrollUpMain = "";
          scrollDownMain = "";
          scrollUpMain-alt1 = "U";
          scrollDownMain-alt1 = "E";
          scrollUpMain-alt2 = "";
          scrollDownMain-alt2 = "";

          executeShellCommand = "!";
        };
      };

      customCommands = [
        {
          key = "<c-l>";
          context = "files";
          command = ''bash -c "lumen draft | tee >(${clipboardCmd})"'';
          loadingText = "Generating message...";
          output = "popup";
        }
        {
          key = "<c-k>";
          context = "files";
          command = ''bash -c "lumen draft -c {{.Form.Context | quote}} | tee >(${clipboardCmd})"'';
          loadingText = "Generating message...";
          output = "popup";
          prompts = [
            {
              type = "input";
              title = "Context";
              key = "Context";
            }
          ];
        }
      ];
    };
  };

  home.shellAliases.lwt = "${pkgs.lazyworktree}/bin/lazyworktree";
  programs.lazyworktree = {
    enable = true;
    package = pkgs.lazyworktree;
    # Configuration settings for lazyworktree
    # See: https://github.com/chmouel/lazyworktree?tab=readme-ov-file#global-configuration-yaml
    settings = {
      editor = "${config.home.sessionVariables.EDITOR}";
      shell = "${pkgs.bash}/bin/bash";
      pager = "${config.home.sessionVariables.PAGER}";
    };
  };
}
