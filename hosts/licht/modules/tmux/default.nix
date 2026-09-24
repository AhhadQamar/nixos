{pkgs, ...}: {
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 10;
    historyLimit = 10000;
    terminal = "tmux-256color";
    extraConfig = builtins.readFile ./config/tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator
    ];
  };
}
