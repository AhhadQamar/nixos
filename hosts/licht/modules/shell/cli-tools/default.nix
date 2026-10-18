{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    bat
    ripgrep
    zoxide
    trash-cli
    (python3Packages.edge-tts.overridePythonAttrs (old: rec {
      version = "7.3.1";
      src = fetchFromGitHub {
        owner = "rany2";
        repo = "edge-tts";
        tag = version;
        hash = "sha256-1Ji1IqOC3iB36N00Ud6LRXyAwRbUrm5iFd1MyCxkbVc=";
      };
    }))
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
