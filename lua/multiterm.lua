if vim.g.loaded_multiterm == 1 then
	return
end
vim.g.loaded_multiterm = 1

local core = require("multiterm.core")
local M = {}

function M.setup(user_opts)
	core.setup(user_opts or {})

	-- Main :Multiterm command
	vim.api.nvim_create_user_command("Multiterm", function(cmd_opts)
		M.toggle_float_term(cmd_opts.count ~= 0 and cmd_opts.count or 0, cmd_opts.bang, 0, cmd_opts.args)
	end, {
		nargs = "*",
		bang = true,
		count = true,
		complete = "shellcmd",
	})

	-- Kill current terminal
	vim.api.nvim_create_user_command("MultitermKillCurrent", function()
		require("multiterm.core").kill_current()
	end, { nargs = 0 })

	-- Kill by tag
	vim.api.nvim_create_user_command("MultitermKill", function(cmd_opts)
		local tag = tonumber(cmd_opts.args)
		require("multiterm.core").kill(tag)
	end, {
		nargs = 1,
		complete = function()
			return { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
		end,
	})

	-- Keymaps for toggle
	vim.keymap.set({ "n", "v" }, "<Plug>(Multiterm)", function()
		M.toggle_float_term(vim.v.count, false, 0, "")
	end, { silent = true })
	vim.keymap.set(
		"i",
		"<Plug>(Multiterm)",
		'<C-o>:lua require("multiterm").toggle_float_term(vim.v.count, false, 0, "")<CR>',
		{ silent = true }
	)
	vim.keymap.set(
		"t",
		"<Plug>(Multiterm)",
		'<C-\\><C-n>:lua require("multiterm").toggle_float_term(vim.v.count, false, 1, "")<CR>',
		{ silent = true }
	)

	-- List. Press d to delete
	vim.keymap.set("n", "<Plug>(MultitermList)", require("multiterm.core").list_terminals)
end

M.toggle_float_term = core.toggle_float_term
return M
