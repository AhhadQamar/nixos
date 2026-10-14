{...}: {
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "rg --files --hidden --follow --glob '!.git'";
    fileWidgetCommand = "rg --files --hidden --follow --glob '!.git'";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border=rounded"
      "--info=inline"
      "--preview-window=right:55%:wrap"
      "--bind=ctrl-d:half-page-down,ctrl-u:half-page-up"
    ];
  };
}
