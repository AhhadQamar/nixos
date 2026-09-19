{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    eza
    bat
    fzf
    ripgrep
    zoxide
    trash-cli
    mpv
    python3Packages.edge-tts
    unzip
    btop

    qrencode
    tealdeer
    jq
    dust
    ncdu
  ];

  programs.zsh = {
    enable = true;

    autosuggestion = {
      enable = true;
      strategy = ["history" "completion"];
    };

    syntaxHighlighting = {
      enable = true;
      highlighters = ["main" "brackets" "pattern" "cursor"];
      styles = {
        command = "fg=cyan,bold";
        alias = "fg=cyan,bold";
        builtin = "fg=cyan,bold";
        function = "fg=cyan,bold";
        unknown-token = "fg=red,bold";
        single-quoted-argument = "fg=yellow";
        double-quoted-argument = "fg=yellow";
        path = "fg=green";
        comment = "fg=8";
        option = "fg=magenta";
      };
    };

    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];

    completionInit = ''
      setopt EXTENDED_GLOB
      autoload -Uz compinit
      zcompdump="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
      mkdir -p "''${zcompdump:h}"
      if [[ -n ''${zcompdump}(#qN.mh+24) ]]; then
        compinit -d "$zcompdump"
      else
        compinit -C -d "$zcompdump"
      fi
      { zcompile "$zcompdump" } &!
    '';

    initContent = lib.mkMerge [
      # Must land before completionInit so compinit picks it up.
      (lib.mkOrder 500 ''
        fpath+=("${pkgs.zsh-completions}/share/zsh/site-functions")
      '')
      (lib.mkOrder 1000 (builtins.readFile ./config/.zshrc))
    ];
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings = builtins.fromTOML (builtins.readFile ./config/starship.toml);
  };
}
