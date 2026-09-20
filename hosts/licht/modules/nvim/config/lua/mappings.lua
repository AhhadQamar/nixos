require("nvchad.mappings")

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- ─── Better Navigation ────────────────────────────────────────────
-- Stay centered when jumping
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down centered" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up centered" })
map("n", "n", "nzzzv", { desc = "Next search centered" })
map("n", "N", "Nzzzv", { desc = "Prev search centered" })

-- Move between splits with Alt+arrows (easier than Ctrl+hjkl for beginners)
map("n", "<A-Left>", "<C-w>h", { desc = "Move to left split" })
map("n", "<A-Right>", "<C-w>l", { desc = "Move to right split" })
map("n", "<A-Up>", "<C-w>k", { desc = "Move to upper split" })
map("n", "<A-Down>", "<C-w>j", { desc = "Move to lower split" })

-- ─── Editing Quality of Life ──────────────────────────────────────
-- Move selected lines up/down in Visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep clipboard when pasting over selection (don't overwrite register)
map("v", "p", '"_dP', { desc = "Paste without yanking" })

-- Delete without yanking (sends to black hole register)
map("n", "<leader>d", '"_d', { desc = "Delete without yank" })
map("v", "<leader>d", '"_d', { desc = "Delete without yank" })

-- Duplicate line
map("n", "<leader>dl", "yyp", { desc = "Duplicate line" })

-- Select all
map("n", "<C-a>", "gg<S-v>G", { desc = "Select all" })

-- Better indent (stay in visual mode after)
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- ─── File & Search ────────────────────────────────────────────────
-- Save with Ctrl+S (like every other editor)
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<CR>", { desc = "Save file" })

-- Quick find and replace word under cursor
map("n", "<leader>rw", ":%s/<C-r><C-w>/<C-r><C-w>/gI<Left><Left><Left>", { desc = "Replace word under cursor" })

-- Clear search highlight
map("n", "<Esc>", "<cmd>noh<CR>", { desc = "Clear search highlight" })

-- ─── LSP ──────────────────────────────────────────────────────────
map("n", "<leader>lf", "<cmd>lua vim.lsp.buf.format()<CR>", { desc = "LSP format" })
map("n", "<leader>la", "<cmd>lua vim.lsp.buf.code_action()<CR>", { desc = "LSP code action" })
map("n", "<leader>lr", "<cmd>lua vim.lsp.buf.rename()<CR>", { desc = "LSP rename" })
map("n", "<leader>ld", "<cmd>lua vim.diagnostic.open_float()<CR>", { desc = "LSP diagnostic float" })
map("n", "]d", "<cmd>lua vim.diagnostic.goto_next()<CR>", { desc = "Next diagnostic" })
map("n", "[d", "<cmd>lua vim.diagnostic.goto_prev()<CR>", { desc = "Prev diagnostic" })

-- ─── Splits ───────────────────────────────────────────────────────
map("n", "<leader>sv", "<cmd>vsplit<CR>", { desc = "Split vertical" })
map("n", "<leader>sh", "<cmd>split<CR>", { desc = "Split horizontal" })
map("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close split" })

-- Resize splits with Ctrl+arrow keys
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Resize up" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Resize down" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Resize left" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Resize right" })

-- ─── Terminal ─────────────────────────────────────────────────────
-- Open terminal at bottom
map("n", "<leader>tt", "<cmd>split | terminal<CR>", { desc = "Open terminal" })
-- Exit terminal mode easily
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
-- ─── LazyGit ──────────────────────────────────────────────────────
map("n", "<leader>gg", "<cmd>LazyGit<CR>", { desc = "Open LazyGit" })
-- ─── Copilot ──────────────────────────────────────────────────────
map("i", "<C-l>", function()
	vim.fn.feedkeys(vim.fn["copilot#Accept"](), "")
end, { desc = "Copilot accept", noremap = true, silent = true })
map("i", "<C-]>", "<Plug>(copilot-dismiss)", { desc = "Copilot dismiss" })
map("i", "<M-]>", "<Plug>(copilot-next)", { desc = "Copilot next" })
map("i", "<M-[>", "<Plug>(copilot-previous)", { desc = "Copilot previous" })
-- ─── Live Server ──────────────────────────────────────────────────
local live_server_job = nil

map("n", "<leader>ls", function()
	if live_server_job then
		vim.notify("live-server is already running", vim.log.levels.WARN)
		return
	end
	local root = vim.fn.expand("%:p:h")
	live_server_job = vim.fn.jobstart({ "live-server", root, "--host", "127.0.0.1", "--port", "5500", "--open" }, {
		on_exit = function()
			live_server_job = nil
		end,
	})
	vim.notify("live-server: http://127.0.0.1:5500")
end, { desc = "Live server start" })

map("n", "<leader>lx", function()
	if live_server_job then
		vim.fn.jobstop(live_server_job)
		live_server_job = nil
		vim.notify("live-server stopped")
	end
end, { desc = "Live server stop" })
