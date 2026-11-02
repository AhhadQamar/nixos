{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    gitleaks
    delta # readable diffs: syntax colours, line numbers, n / N between files
    gh-dash # pull requests and issues in a terminal dashboard: `gh dash`
  ];

  programs.git = {
    enable = true;

    settings = {
      user.name = "AhhadQamar";
      user.email = "ahadqam1@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = false;

      # Diffs and pagers
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        line-numbers = true;
      };
      diff.algorithm = "histogram";
      diff.colorMoved = "default";

      # Conflicts: show the common ancestor too, and remember how each one was
      # resolved so a repeated rebase does not ask again
      merge.conflictStyle = "zdiff3";
      rerere.enabled = true;

      # Less typing
      push.autoSetupRemote = true; # first push of a branch needs no -u
      push.followTags = true;
      fetch.prune = true;
      rebase.autoStash = true; # rebase with a dirty tree
      rebase.autoSquash = true; # fixup! commits go where they belong
      rebase.updateRefs = true; # stacked branches follow a rebase
      commit.verbose = true; # the diff in the commit message editor
      branch.sort = "-committerdate"; # recent branches first
      tag.sort = "version:refname";
      help.autocorrect = "prompt";
      core.sshCommand = "ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes";
    };

    # Never worth committing, in any repo
    ignores = [
      ".direnv/"
      ".env"
      "*.swp"
      ".DS_Store"
    ];

    includes = [
      {
        condition = "gitdir:~/Projects/work/";
        contents = {
          user = {
            name = "MuhammadAhhadQumar";
            email = "ahhadqamar1@gmail.com";
          };
          core.sshCommand = "ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes";
        };
      }
    ];
  };

  # `lg` (or Super+... in a terminal): staging, rebasing and history without
  # typing git commands
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        nerdFontsVersion = "3";
        showFileTree = true;
      };
      # A list since lazygit 0.54 (it used to be a single `git.paging`)
      git.pagers = [
        {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        }
      ];
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}
