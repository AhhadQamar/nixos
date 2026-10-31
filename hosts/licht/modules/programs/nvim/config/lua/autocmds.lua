-- ~/.config/nvim/lua/autocmds.lua

-- QML filetype detection (for Quickshell)
vim.filetype.add {
  extension = { qml = "qml" },
}

-- Jinja templates (Flask): treat as htmldjango so prettier is skipped
vim.filetype.add {
  extension = { jinja = "htmldjango", jinja2 = "htmldjango", j2 = "htmldjango" },
  pattern = {
    [".*/templates/.*%.html"] = "htmldjango",
    [".*%.html%.j2"] = "htmldjango",
  },
}

-- QML indentation
vim.api.nvim_create_autocmd("FileType", {
  pattern = "qml",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.expandtab = true
  end,
})

-- cssls: start on CSS files
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = { "*.css", "*.scss", "*.less" },
  callback = function()
    vim.lsp.start {
      name = "cssls",
      cmd = { "vscode-css-language-server", "--stdio" },
      filetypes = { "css", "scss", "less" },
      root_dir = vim.fn.getcwd(),
      settings = {
        css = { validate = true, lint = { unknownAtRules = "ignore" } },
        scss = { validate = true },
        less = { validate = true },
      },
    }
  end,
})
