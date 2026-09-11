-- ~/.config/nvim/lua/configs/treesitter.lua
-- Modern nvim-treesitter API (nvim-treesitter.configs no longer exists)

vim.treesitter.language.register("qmljs", "qml")

local parsers = {
  "vim", "lua", "vimdoc",
  "html", "css", "javascript", "typescript", "tsx", "json", "markdown",
  "c", "cpp", "cmake", "make",
  "python",
  "qmljs",
  "bash", "yaml", "toml", "dockerfile",
}

-- Install any missing parsers
local installed = require("nvim-treesitter.config").get_installed()
local to_install = vim.tbl_filter(function(p)
  return not vim.tbl_contains(installed, p)
end, parsers)

if #to_install > 0 then
  require("nvim-treesitter").install(to_install)
end

-- Enable highlighting + indentation on every filetype
vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    pcall(vim.treesitter.start)
    vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})
