{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    neovim
    lazygit
    nodejs
    tree-sitter
    gcc
    lua
    nil
    alejandra

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

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nixos/hosts/licht/modules/nvim/config";
}
