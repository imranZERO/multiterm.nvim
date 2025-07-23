local M = {}

local default_opts = {
	height = 0.8,
	width = 0.8,
	height_value = function(self)
		return math.floor(vim.o.lines * self.height)
	end,
	width_value = function(self)
		return math.floor(vim.o.columns * self.width)
	end,
	row = function(self)
		local h = type(self.height_value) == "function" and self.height_value(self) or self.height_value
		return math.floor((vim.o.lines - h) / 2)
	end,
	col = function(self)
		local w = type(self.width_value) == "function" and self.width_value(self) or self.width_value
		return math.floor((vim.o.columns - w) / 2)
	end,
	border = "rounded",
	term_hl = "Normal",
	border_hl = "FloatBorder",
	show_backdrop = true,
	backdrop_bg = "Black",
	backdrop_transparency = 60,
	fullscreen = false,
	show_tab = true,
	tabline_hl_cur = "PmenuSel", -- highlight group for active tag
	tabline_hl_other = "Pmenu", -- for inactive
}

local opts = {}

local tab_buf, tab_win

local term_buf_active_count = 0
local term_buf_active_counts = {}
local term_bufs = {}
local term_wins = {}
local term_last_wins = {}
local term_tmodes = {}
local backdrop_wins = {}
local tag_wins = {}

for i = 0, 9 do
	term_buf_active_counts[i] = 0
end

function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", {}, default_opts, user_opts or {})
end

local function get_term_tag(tag)
	if tag < 0 or tag > 9 then
		vim.notify("Invalid terminal tag: " .. tag, vim.log.levels.ERROR)
		return 0
	end
	if tag == 0 then
		local max_tag, max_count = 1, 0
		for i = 1, 9 do
			if term_bufs[i] and vim.api.nvim_buf_is_valid(term_bufs[i]) and term_buf_active_counts[i] > max_count then
				max_tag, max_count = i, term_buf_active_counts[i]
			end
		end
		return max_tag
	else
		return tag
	end
end

local function create_backdrop(tag)
	if not opts.show_backdrop then
		return nil, nil
	end

	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	local backdrop_opts = {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = 10, -- Behind terminal and tag overlay
	}
	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, backdrop_opts)
	vim.api.nvim_set_hl(0, "MultitermBackdrop", { bg = opts.backdrop_bg })
	vim.api.nvim_win_set_option(backdrop_win, "winhighlight", "Normal:MultitermBackdrop")
	vim.api.nvim_win_set_option(backdrop_win, "winblend", opts.backdrop_transparency)
	vim.api.nvim_buf_set_option(backdrop_buf, "bufhidden", "wipe")
	backdrop_wins[tag] = backdrop_win
	return backdrop_buf, backdrop_win
end

function M.toggle_float_term(tag, no_close, tmode, cmd)
	tag = get_term_tag(tag or 0)
	if tag == 0 then
		return
	end

	-- If user passed a command, ensure buffer is killed before opening a new terminal
	if cmd ~= "" and term_bufs[tag] and vim.api.nvim_buf_is_valid(term_bufs[tag]) then
		M._do_kill(tag)
	end

	-- Dynamically calculate dimensions based on current window size
	local height = type(opts.height_value) == "function" and opts.height_value(opts) or opts.height_value
	local width = type(opts.width_value) == "function" and opts.width_value(opts) or opts.width_value
	local row = type(opts.row) == "function" and opts.row(opts) or opts.row
	local col = type(opts.col) == "function" and opts.col(opts) or opts.col

	if opts.fullscreen then
		height = vim.o.lines - 2
		width = vim.o.columns - 2
		row = 1
		col = 1
	end

	local win_opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border,
	}

	if not term_wins[tag] or not vim.api.nvim_win_is_valid(term_wins[tag]) then
		term_last_wins[tag] = vim.api.nvim_get_current_win()

		local backdrop_buf, backdrop_win = create_backdrop(tag)

		local need_termopen = false
		if not term_bufs[tag] or not vim.api.nvim_buf_is_valid(term_bufs[tag]) then
			term_bufs[tag] = vim.api.nvim_create_buf(false, false)
			need_termopen = true
		end

		term_wins[tag] = vim.api.nvim_open_win(term_bufs[tag], true, win_opts)
		vim.api.nvim_win_set_option(term_wins[tag], "winhighlight", "NormalFloat:" .. opts.term_hl)
		vim.api.nvim_win_set_var(term_wins[tag], "_multiterm_term_tag", tag)

		M.update_tab(tag)

		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = term_bufs[tag],
			once = true,
			callback = function()
				if term_wins[tag] then
					pcall(vim.api.nvim_win_close, term_wins[tag], true)
					term_wins[tag] = nil
				end
				if backdrop_win and backdrop_buf then
					pcall(vim.api.nvim_buf_delete, backdrop_buf, { force = true })
					pcall(vim.api.nvim_win_close, backdrop_win, true)
					backdrop_wins[tag] = nil
				end
				if tab_win and vim.api.nvim_win_is_valid(tab_win) then
					pcall(vim.api.nvim_win_close, tab_win, true)
					tab_buf, tab_win = nil, nil
				end
				term_tmodes[tag] = 0
			end,
		})

		if need_termopen then
			vim.fn.termopen((cmd ~= "" and cmd) or vim.o.shell, {
				on_exit = function(_, exit_code)
					-- only auto close on success (0), and only if user didn’t add “!”
					if exit_code == 0 and not no_close then
						if term_bufs[tag] and vim.api.nvim_buf_is_valid(term_bufs[tag]) then
							vim.api.nvim_buf_delete(term_bufs[tag], { force = true })
							term_bufs[tag] = nil
						end
					end
				end,
			})
			vim.cmd("startinsert")
		elseif term_tmodes[tag] == 1 and vim.api.nvim_get_mode().mode ~= "t" then
			vim.cmd("startinsert")
		end

		term_buf_active_count = term_buf_active_count + 1
		term_buf_active_counts[tag] = term_buf_active_count
	else
		pcall(vim.api.nvim_win_close, term_wins[tag], true)
		term_wins[tag] = nil
		if backdrop_wins[tag] then
			pcall(vim.api.nvim_win_close, backdrop_wins[tag], true)
			backdrop_wins[tag] = nil
		end
		if term_last_wins[tag] and vim.api.nvim_win_is_valid(term_last_wins[tag]) then
			vim.api.nvim_set_current_win(term_last_wins[tag])
		end
		if tab_win and vim.api.nvim_win_is_valid(tab_win) then
			pcall(vim.api.nvim_win_close, tab_win, true)
			tab_buf, tab_win = nil, nil
		end
		term_tmodes[tag] = tmode
	end
end

function M.list_terminals()
	local terms = {}
	for tag = 1, 9 do
		if term_bufs[tag] and vim.api.nvim_buf_is_valid(term_bufs[tag]) then
			table.insert(terms, string.format("Term %d (buf: %d)", tag, term_bufs[tag]))
		end
	end

	if #terms == 0 then
		vim.notify("No active Multiterm windows found.", vim.log.levels.INFO)
		return
	end

	-- Create a scratch buffer for the popup
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, terms)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Calculate window size
	local unpack_ = table.unpack or rawget(_G, "unpack") -- Lua 5.2+ or fallback to 5.1
	local width = math.max(unpack_(vim.tbl_map(string.len, terms))) + 4
	local height = #terms + 2
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Create the floating window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = opts.border,
		title = " Multiterms ",
		title_pos = "center",
		zindex = 200,
	})

	-- Set window options
	vim.api.nvim_win_set_option(
		win,
		"winhighlight",
		"NormalFloat:" .. opts.term_hl .. ",FloatBorder:" .. opts.border_hl
	)
	vim.api.nvim_win_set_option(win, "winblend", 0)
	vim.api.nvim_win_set_option(win, "cursorline", true)

	local function select_terminal(tag)
		if term_bufs[tag] and vim.api.nvim_buf_is_valid(term_bufs[tag]) then
			vim.api.nvim_win_close(win, true)
			if not term_wins[tag] or not vim.api.nvim_win_is_valid(term_wins[tag]) then
				M.toggle_float_term(tag, false, term_tmodes[tag] or 0)
			else
				vim.api.nvim_set_current_win(term_wins[tag])
				if term_tmodes[tag] == 1 and vim.api.nvim_get_mode().mode ~= "t" then
					vim.cmd("startinsert")
				end
			end
		else
			vim.api.nvim_win_close(win, true)
			vim.notify("Terminal " .. tag .. " is not active.", vim.log.levels.WARN)
		end
	end

	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		callback = function()
			local line = vim.api.nvim_get_current_line()
			local tag = tonumber(line:match("Term (%d+)"))
			if tag then
				select_terminal(tag)
			else
				vim.api.nvim_win_close(win, true)
				vim.notify("Invalid terminal selection.", vim.log.levels.WARN)
			end
		end,
		silent = true,
	})

	-- delete terminal by pressing d
	vim.keymap.set("n", "d", function()
		local line = vim.api.nvim_get_current_line()
		local tag = tonumber(line:match("Term (%d+)"))
		if not tag then
			return
		end

		M._do_kill(tag)

		local new = {}
		for t = 1, 9 do
			if term_bufs[t] and vim.api.nvim_buf_is_valid(term_bufs[t]) then
				table.insert(new, string.format("Term %d (buf: %d)", t, term_bufs[t]))
			end
		end

		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
		vim.api.nvim_buf_set_option(buf, "modifiable", false)

		-- keep the cursor on the same line
		local cur = vim.api.nvim_win_get_cursor(win)[1]
		local line_count = #new
		if line_count > 0 then
			local ln = math.min(cur, line_count)
			vim.api.nvim_win_set_cursor(win, { ln, 0 })
		end

		-- force a redraw
		vim.cmd("redraw")

		if #new == 0 then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, silent = true, nowait = true })

	for _, key in ipairs({ "<Up>", "k", "<Down>", "j" }) do
		vim.api.nvim_buf_set_keymap(buf, "n", key, ":normal! " .. key .. "<CR>", { silent = true })
	end

	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
		callback = function()
			vim.api.nvim_win_close(win, true)
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		callback = function()
			vim.api.nvim_win_close(win, true)
		end,
	})

	-- Auto-close when leaving the buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		once = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
end

--- kill everything for a given tag
function M._do_kill(tag)
	if not (tag and term_bufs[tag]) then
		return
	end
	if term_wins[tag] and vim.api.nvim_win_is_valid(term_wins[tag]) then
		vim.api.nvim_win_close(term_wins[tag], true)
	end
	if tag_wins[tag] and vim.api.nvim_win_is_valid(tag_wins[tag]) then
		vim.api.nvim_win_close(tag_wins[tag], true)
	end
	if backdrop_wins[tag] and vim.api.nvim_win_is_valid(backdrop_wins[tag]) then
		vim.api.nvim_win_close(backdrop_wins[tag], true)
	end
	-- delete the buffer
	if vim.api.nvim_buf_is_valid(term_bufs[tag]) then
		vim.api.nvim_buf_delete(term_bufs[tag], { force = true })
	end
	if tab_win and vim.api.nvim_win_is_valid(tab_win) then
		pcall(vim.api.nvim_win_close, tab_win, true)
		tab_buf, tab_win = nil, nil
	end
	term_bufs[tag] = nil
	term_wins[tag] = nil
	tag_wins[tag] = nil
	backdrop_wins[tag] = nil
	term_tmodes[tag] = nil
	term_buf_active_counts[tag] = 0
end

--- kill the terminal buffer for the current buffer
function M.kill_current()
	local cur = vim.api.nvim_get_current_buf()
	for tag, buf in pairs(term_bufs) do
		if buf == cur then
			M._do_kill(tag)
			return
		end
	end
	vim.notify("Not in a Multiterm buffer", vim.log.levels.WARN)
end

--- kill the terminal buffer by tag
function M.kill(tag)
	if not (tag and term_bufs[tag]) then
		vim.notify("No such terminal: " .. tostring(tag), vim.log.levels.ERROR)
		return
	end
	M._do_kill(tag)
end

-- Render the tab bar
local function render_tab()
	local bits = {}
	for t = 1, 9 do
		if term_bufs[t] and vim.api.nvim_buf_is_valid(term_bufs[t]) then
			table.insert(bits, string.format("[%d]", t))
		end
	end
	return table.concat(bits, " ")
end

-- ensure tabline window exists
local function ensure_tabline()
	if not opts.show_tab then
		return
	end

	local active_term_win = nil
	for t = 1, 9 do
		if term_wins[t] and vim.api.nvim_win_is_valid(term_wins[t]) then
			active_term_win = term_wins[t]
			break
		end
	end

	if not active_term_win then
		return
	end

	if tab_buf and vim.api.nvim_buf_is_valid(tab_buf) then
		return
	end

	tab_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(tab_buf, "bufhidden", "wipe")

	local term_config = vim.api.nvim_win_get_config(active_term_win)
	local line = render_tab(0)
	local tabline_width = #line

	tab_win = vim.api.nvim_open_win(tab_buf, false, {
		relative = "editor",
		anchor = "NE",
		width = tabline_width,
		height = 1,
		row = term_config.row,
		col = term_config.col + term_config.width - 2,
		style = "minimal",
		border = nil,
		focusable = false,
		zindex = 60,
	})

	vim.api.nvim_win_set_option(tab_win, "winhighlight", "Normal:" .. opts.border_hl)
end

function M.update_tab(active_tag)
	if not opts.show_tab then
		return
	end

	local any_visible = false
	for t = 1, 9 do
		if term_wins[t] and vim.api.nvim_win_is_valid(term_wins[t]) then
			any_visible = true
			break
		end
	end

	if not any_visible then
		if tab_win and vim.api.nvim_win_is_valid(tab_win) then
			pcall(vim.api.nvim_win_close, tab_win, true)
			tab_buf, tab_win = nil, nil
		end
		return
	end

	ensure_tabline()
	local line = render_tab()
	vim.api.nvim_buf_set_option(tab_buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(tab_buf, 0, -1, false, { line })
	vim.api.nvim_buf_set_option(tab_buf, "modifiable", false)

	local active_term_win = nil
	for t = 1, 9 do
		if term_wins[t] and vim.api.nvim_win_is_valid(term_wins[t]) then
			active_term_win = term_wins[t]
			break
		end
	end

	if active_term_win then
		local term_config = vim.api.nvim_win_get_config(active_term_win)
		local tabline_width = #line

		vim.api.nvim_win_set_config(tab_win, {
			relative = "editor",
			anchor = "NE",
			width = tabline_width,
			height = 1,
			row = term_config.row,
			col = term_config.col + term_config.width - 2,
			style = "minimal",
			border = nil,
			focusable = false,
			zindex = 60,
		})
	end

	vim.api.nvim_buf_clear_namespace(tab_buf, -1, 0, -1)
	local col = 0
	for t = 1, 9 do
		if term_bufs[t] and vim.api.nvim_buf_is_valid(term_bufs[t]) then
			local text = string.format("[%d]", t)
			local len = #text
			local hl = (t == active_tag) and opts.tabline_hl_cur or opts.tabline_hl_other
			vim.api.nvim_buf_add_highlight(tab_buf, -1, hl, 0, col, col + len)
			col = col + len + 1 
		end
	end
end

function M.next_term()
	local tags = {}
	for t = 1, 9 do
		if term_bufs[t] and vim.api.nvim_buf_is_valid(term_bufs[t]) then
			table.insert(tags, t)
		end
	end
	if #tags == 0 then
		return
	end

	local cur_buf = vim.api.nvim_get_current_buf()
	local cur_idx = 1
	for i, t in ipairs(tags) do
		if term_bufs[t] == cur_buf then
			cur_idx = i
			break
		end
	end

	local next_tag = tags[(cur_idx % #tags) + 1]
	M.toggle_float_term(next_tag, false, 0, "")
end

function M.prev_term()
	local tags = {}
	for t = 1, 9 do
		if term_bufs[t] and vim.api.nvim_buf_is_valid(term_bufs[t]) then
			table.insert(tags, t)
		end
	end
	if #tags == 0 then
		return
	end

	local cur_buf = vim.api.nvim_get_current_buf()
	local cur_idx = 1
	for i, t in ipairs(tags) do
		if term_bufs[t] == cur_buf then
			cur_idx = i
			break
		end
	end

	local prev_tag = tags[((cur_idx - 2) % #tags) + 1]
	M.toggle_float_term(prev_tag, false, 0, "")
end

return M
