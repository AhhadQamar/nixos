{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    gitleaks
  ];

  programs.git = {
    enable = true;

    settings = {
      user.name = "AhhadQamar";
      user.email = "ahadqam1@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = false;
      core.sshCommand = "ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes";
    };

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

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}
