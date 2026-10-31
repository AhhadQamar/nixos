-- ~/.config/nvim/lua/configs/conform.lua

local options = {
	formatters_by_ft = {
		-- Web
		html = { "prettier" },
		css = { "prettier" },
		javascript = { "prettier" },
		typescript = { "prettier" },
		json = { "prettier" },
		markdown = { "prettier" },

		-- Jinja templates (Flask) - prettier breaks {% %} / {{ }}
		htmldjango = { "djlint" },

		-- C / C++
		c = { "clang_format" },
		cpp = { "clang_format" },

		-- Python
		python = { "black", "isort" },

		-- QML (Quickshell)
		qml = { "qmlformat" },

		-- Nix
		nix = { "alejandra" },

		-- Lua (your Neovim config)
		lua = { "stylua" },
	},

	-- Formatters with custom settings
	formatters = {
		black = {
			prepend_args = { "--fast", "--line-length", "88" },
		},
		djlint = {
			prepend_args = { "--profile", "jinja", "--indent", "2" },
		},
		isort = {
			prepend_args = { "--profile", "black" },
		},
		clang_format = {
			prepend_args = {
				"-style={ IndentWidth: 4, TabWidth: 4, UseTab: Never }",
			},
		},
	},

	-- Format automatically when you save a file
	-- djlint is a Python tool with a slow cold start, give it more time
	format_on_save = function(bufnr)
		local slow = { htmldjango = true }
		return {
			timeout_ms = slow[vim.bo[bufnr].filetype] and 10000 or 2000,
			lsp_format = "fallback",
		}
	end,
}

require("conform").setup(options)
