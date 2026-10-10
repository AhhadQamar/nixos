{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    bat
    ripgrep
    zoxide
    trash-cli
    python3Packages.edge-tts
    python3Packages.docx2txt
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
