{
  config,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    neovim
    lazygit
    nodejs
    tree-sitter
    gcc
    lua
    nil
    nixfmt

    # LSP servers
    vscode-langservers-extracted # html, css, json, eslint
    typescript-language-server
    typescript
    emmet-language-server
    tailwindcss-language-server
    pyright
    lua-language-server
    clang-tools # clangd + clang-format
    kdePackages.qtdeclarative # qmlls6, qmlformat

    stylua
    prettier
    black
    python3Packages.isort
  ];

  # ~/.config/nvim points directly at the repo checkout instead of a
  # read-only copy in the Nix store, so lazy.nvim (and anything else that
  # writes into "nvim config") can actually write there -- lazy-lock.json
  # included. This is the flake root on this machine; update the path if
  # the repo ever moves.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/etc/nixos/hosts/licht/modules/nvim/config";
}
