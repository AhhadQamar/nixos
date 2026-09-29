{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    bat
    ripgrep
    zoxide
    trash-cli
    python3Packages.edge-tts
    unzip
    _7zz
    unrar
    btop

    qrencode
    tealdeer
    jq
    dust
    ncdu
  ];
}
