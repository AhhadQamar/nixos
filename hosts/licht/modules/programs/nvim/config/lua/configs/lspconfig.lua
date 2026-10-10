-- ~/.config/nvim/lua/configs/lspconfig.lua
require("nvchad.configs.lspconfig").defaults()
local servers = {
	"html",
	"cssls",
	"jsonls",
	"ts_ls",
	"eslint",
	"emmet_language_server",
	"tailwindcss",
	"pyright",
	"lua_ls",
	"nil_ls",
}
vim.lsp.enable(servers)
-- nil_ls: auto-fetch flake inputs instead of prompting every time
vim.lsp.config("nil_ls", {
	settings = {
		["nil"] = {
			nix = {
				flake = {
					autoArchive = true,
				},
			},
		},
	},
})
-- clangd: disable built-in formatter
vim.lsp.config("clangd", {
	on_attach = function(client, bufnr)
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
		require("nvchad.configs.lspconfig").on_attach(client, bufnr)
	end,
})
vim.lsp.enable("clangd")
-- qmlls6: system binary from qt6-tools
vim.lsp.config("qmlls6", {
	cmd = { "qmlls6" },
	filetypes = { "qml" },
	root_markers = { "CMakeLists.txt", ".git", "qmldir" },
})
vim.lsp.enable("qmlls6")
