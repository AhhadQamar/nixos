-- ~/.config/nvim/lua/configs/conform.lua

local options = {
  formatters_by_ft = {
    -- Web
    html       = { "prettier" },
    css        = { "prettier" },
    javascript = { "prettier" },
    typescript = { "prettier" },
    json       = { "prettier" },
    markdown   = { "prettier" },

    -- C / C++
    c   = { "clang_format" },
    cpp = { "clang_format" },

    -- Python
    python = { "black", "isort" },

    -- QML (Quickshell)
    qml = { "qmlformat" },

    -- Nix
    nix = { "nixfmt" },

    -- Lua (your Neovim config)
    lua = { "stylua" },
  },

  -- Formatters with custom settings
  formatters = {
    black = {
      prepend_args = { "--fast", "--line-length", "88" },
    },
    isort = {
      prepend_args = { "--profile", "black" },
    },
    ["clang-format"] = {
      prepend_args = {
        "-style={ IndentWidth: 4, TabWidth: 4, UseTab: Never }",
      },
    },
  },

  -- Format automatically when you save a file
  format_on_save = {
    timeout_ms = 2000,
    lsp_fallback = true,
  },
}

require("conform").setup(options)
