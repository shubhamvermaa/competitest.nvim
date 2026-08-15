local api = vim.api
local config = require("competitest.config")
local testcases = require("competitest.testcases")
local utils = require("competitest.utils")
local widgets = require("competitest.widgets")
local M = {}

---Handle CompetiTest subcommands
---@param arguments string command line arguments
function M.command(arguments)
	local args = vim.split(arguments, " ", { plain = true, trimempty = true })
	if not args[1] then
		utils.notify("command: at least one argument required.")
		return
	end

	---Check if current subcommand has the correct number of arguments
	---@param min_args integer
	---@param max_args integer
	---@return boolean
	local function check_subargs(min_args, max_args)
		local count = #args - 1
		if min_args <= count and count <= max_args then
			return true
		end
		if min_args == max_args then
			utils.notify(string.format("command: %s: exactly %d sub-arguments required.", args[1], min_args))
		else
			utils.notify(string.format("command: %s: from %d to %d sub-arguments required.", args[1], min_args, max_args))
		end
		return false
	end

	---@type table<string, fun()>
	local subcommands = {
		add_testcase = function()
			if check_subargs(0, 0) then
				M.edit_testcase(true)
			end
		end,
		edit_testcase = function()
			if check_subargs(0, 1) then
				M.edit_testcase(false, tonumber(args[2]))
			end
		end,
		delete_testcase = function()
			if check_subargs(0, 1) then
				M.delete_testcase(tonumber(args[2]))
			end
		end,
		convert = function()
			if check_subargs(1, 1) then
				M.convert_testcases(args[2])
			end
		end,
		run = function()
			local testcases_list = nil
			if args[2] then
				testcases_list = { unpack(args, 2) }
			end
			M.run_testcases(testcases_list, true, false)
		end,
		run_no_compile = function()
			local testcases_list = nil
			if args[2] then
				testcases_list = { unpack(args, 2) }
			end
			M.run_testcases(testcases_list, false, false)
		end,
		show_ui = function()
			if check_subargs(0, 0) then
				M.run_testcases(nil, false, true)
			end
		end,
		receive = function()
			if check_subargs(1, 1) then
				M.receive(args[2])
			end
		end,
		submit = function()
			if check_subargs(0, 1) then
				M.submit_solution(args[2])
			end
		end,
	}

	local sub = subcommands[args[1]]
	if not sub then
		utils.notify("command: subcommand '" .. args[1] .. "' doesn't exist!")
	else
		sub()
	end
end

---Start testcase editor to add a new testcase or to edit a testcase that already exists
---@param add_testcase boolean if `true` a new testcases will be added, otherwise edit a testcase that already exists
---@param tcnum integer? testcase number
function M.edit_testcase(add_testcase, tcnum)
	local bufnr = api.nvim_get_current_buf()
	config.load_buffer_config(bufnr) -- reload buffer configuration since it may have been updated in the meantime
	local tctbl = testcases.buf_get_testcases(bufnr)
	if add_testcase then
		tcnum = 1
		while tctbl[tcnum] do
			tcnum = tcnum + 1
		end
		tctbl[tcnum] = { input = "", output = "" }
	end

	---Start testcase editor to edit a testcase
	---@param tcnum integer testcase number
	---@diagnostic disable-next-line: redefined-local
	local function start_editor(tcnum)
		if not tctbl[tcnum] then
			utils.notify("edit_testcase: testcase " .. tostring(tcnum) .. " doesn't exist!")
			return
		end

		---Save edited testcase
		---@param tc competitest.FullTestcase
		local function save_data(tc)
			if config.get_buffer_config(bufnr).testcases_use_single_file then
				tctbl[tcnum] = tc
				testcases.single_file.buf_write(bufnr, tctbl)
			else
				testcases.io_files.buf_write_pair(bufnr, tcnum, tc.input, tc.output)
			end
		end

		widgets.editor(bufnr, tcnum, tctbl[tcnum].input, tctbl[tcnum].output, save_data, api.nvim_get_current_win())
	end

	if not tcnum then
		widgets.picker(bufnr, tctbl, "Edit a Testcase", start_editor, api.nvim_get_current_win())
	else
		start_editor(tcnum)
	end
end

---Delete a testcase
---@param tcnum integer? testcase number
function M.delete_testcase(tcnum)
	local bufnr = api.nvim_get_current_buf()
	config.load_buffer_config(bufnr) -- reload buffer configuration since it may have been updated in the meantime
	local tctbl = testcases.buf_get_testcases(bufnr)

	---Delete a testcase
	---@param tcnum integer testcase number
	---@diagnostic disable-next-line: redefined-local
	local function delete_testcase(tcnum) -- item.id is testcase number
		if not tctbl[tcnum] then
			utils.notify("delete_testcase: testcase " .. tostring(tcnum) .. " doesn't exist!")
			return
		end

		local choice = vim.fn.confirm("Are you sure you want to delete Testcase " .. tcnum .. "?", "Yes\nNo")
		if choice == 0 or choice == 2 then
			return
		end -- user pressed <esc> or chose "No"

		if config.get_buffer_config(bufnr).testcases_use_single_file then
			tctbl[tcnum] = nil
			testcases.single_file.buf_write(bufnr, tctbl)
		else
			testcases.io_files.buf_write_pair(bufnr, tcnum, nil, nil)
		end
	end

	if not tcnum then
		widgets.picker(bufnr, tctbl, "Delete a Testcase", delete_testcase, api.nvim_get_current_win())
	else
		delete_testcase(tcnum)
	end
end

---Convert testcases from single file to multiple files and vice versa
---@param mode "singlefile_to_files" | "files_to_singlefile" | "auto"
function M.convert_testcases(mode)
	local bufnr = api.nvim_get_current_buf()
	local singlefile_tctbl = testcases.single_file.buf_load(bufnr)
	local no_singlefile = next(singlefile_tctbl) == nil
	local files_tctbl = testcases.io_files.buf_load(bufnr)
	local no_files = next(files_tctbl) == nil

	local function convert_singlefile_to_files()
		if no_singlefile then
			utils.notify("convert_testcases: there's no single file containing testcases.")
			return
		end
		if not no_files then
			local choice = vim.fn.confirm("Testcases files already exist, by proceeding they will be replaced.", "Proceed\nCancel")
			if choice == 0 or choice == 2 then
				return
			end -- user pressed <esc> or chose "Cancel"
		end

		for tcnum, _ in pairs(files_tctbl) do -- delete already existing files
			testcases.io_files.buf_write_pair(bufnr, tcnum, nil, nil)
		end
		testcases.single_file.buf_write(bufnr, {}) -- delete single file
		testcases.io_files.buf_write(bufnr, singlefile_tctbl) -- create new files
	end

	local function convert_files_to_singlefile()
		if no_files then
			utils.notify("convert_testcases: there are no files containing testcases.")
			return
		end
		if not no_singlefile then
			local choice = vim.fn.confirm("Testcases single file already exists, by proceeding it will be replaced.", "Proceed\nCancel")
			if choice == 0 or choice == 2 then
				return
			end -- user pressed <esc> or chose "Cancel"
		end

		for tcnum, _ in pairs(files_tctbl) do -- delete already existing files
			testcases.io_files.buf_write_pair(bufnr, tcnum, nil, nil)
		end
		testcases.single_file.buf_write(bufnr, files_tctbl) -- create new single file
	end

	if mode == "singlefile_to_files" then
		convert_singlefile_to_files()
	elseif mode == "files_to_singlefile" then
		convert_files_to_singlefile()
	elseif mode == "auto" then
		if no_singlefile and no_files then
			utils.notify("convert_testcases: there's nothing to convert.")
		elseif not no_singlefile and not no_files then
			utils.notify("convert_testcases: single file and testcases files exist, please specifify what's to be converted.")
		elseif no_singlefile then
			convert_files_to_singlefile()
		else
			convert_singlefile_to_files()
		end
	else
		utils.notify("convert_testcases: unrecognized mode '" .. tostring(mode) .. "'.")
	end
end

---Runners associated with each buffer
---@type table<integer, competitest.TCRunner>
M.runners = {}

---Unload a runner and clean up its UI windows
---@param bufnr integer
function M.remove_runner(bufnr)
	bufnr = tonumber(bufnr)
	if bufnr and M.runners[bufnr] then
		local r = M.runners[bufnr]
		pcall(function() r:kill_all_processes() end)
		if r.ui then
			pcall(function() r.ui:delete() end)
		end
		M.runners[bufnr] = nil

		-- If only orphan/nofile/CompetiTest windows remain, close them cleanly
		pcall(function()
			local remaining_wins = api.nvim_tabpage_list_wins(0)
			local has_normal_win = false
			for _, w in ipairs(remaining_wins) do
				if api.nvim_win_is_valid(w) then
					local b = api.nvim_win_get_buf(w)
					local ft = vim.bo[b].filetype
					local bt = vim.bo[b].buftype
					if ft ~= "CompetiTest" and bt ~= "nofile" and bt ~= "prompt" and bt ~= "quickfix" then
						has_normal_win = true
						break
					end
				end
			end
			if not has_normal_win and #remaining_wins > 0 then
				for _, w in ipairs(remaining_wins) do
					if api.nvim_win_is_valid(w) then
						pcall(api.nvim_win_close, w, true)
					end
				end
			end
		end)
	end
end

---Start testcases runner
---@param testcases_list string[]? list with integers representing testcases to run, or `nil` to run all the testcases
---@param compile boolean whether to compile or not
---@param only_show boolean if `true` show previously closed CompetiTest windows without executing testcases
function M.run_testcases(testcases_list, compile, only_show)
	local bufnr = api.nvim_get_current_buf()
	if not only_show then
		api.nvim_buf_call(bufnr, function()
			vim.cmd("silent! update")
		end)
	end
	config.load_buffer_config(bufnr)
	local tctbl = testcases.buf_get_testcases(bufnr)

	local normalized_tctbl = {}
	local keys = {}
	for k in pairs(tctbl) do
		if type(k) == "number" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	for i, k in ipairs(keys) do
		normalized_tctbl[i] = tctbl[k]
	end
	tctbl = normalized_tctbl

	if testcases_list then
		---@type competitest.TcTable
		local new_tctbl = {}
		for _, tcnum in ipairs(testcases_list) do
			local num = tonumber(tcnum)
			if not num or not tctbl[num] then -- invalid testcase
				utils.notify("run_testcases: testcase " .. tcnum .. " doesn't exist!")
			else
				new_tctbl[num] = tctbl[num]
			end
		end
		tctbl = new_tctbl
	end

	if next(tctbl) == nil then
		tctbl[1] = { input = "", output = nil }
	end

	-- Close runner UIs of any other buffers so only current problem UI is shown
	for other_buf, runner in pairs(M.runners) do
		if other_buf ~= bufnr and runner.ui and runner.ui.ui_visible then
			pcall(function() runner.ui:delete() end)
		end
	end

	if not M.runners[bufnr] then -- no runner is associated to buffer
		M.runners[bufnr] = require("competitest.runner"):new(bufnr)
		if not M.runners[bufnr] then -- an error occurred
			return
		end

		local augroup = api.nvim_create_augroup("CompetiTestRunner_" .. bufnr, { clear = true })
		api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
			group = augroup,
			buffer = bufnr,
			callback = function()
				vim.schedule(function()
					M.remove_runner(bufnr)
				end)
			end,
		})
		api.nvim_create_autocmd("WinClosed", {
			group = augroup,
			pattern = "*",
			callback = function(args)
				local closed_win = tonumber(args.match)
				vim.schedule(function()
					local wins = vim.fn.win_findbuf(bufnr)
					if #wins == 0 or (#wins == 1 and wins[1] == closed_win) then
						M.remove_runner(bufnr)
					end
				end)
			end,
		})
		api.nvim_create_autocmd({ "BufHidden", "BufLeave" }, {
			group = augroup,
			buffer = bufnr,
			callback = function()
				vim.schedule(function()
					local wins = vim.fn.win_findbuf(bufnr)
					if #wins == 0 and M.runners[bufnr] and M.runners[bufnr].ui and M.runners[bufnr].ui.ui_visible then
						pcall(function() M.runners[bufnr].ui:delete() end)
					end
				end)
			end,
		})
	end
	local r = M.runners[bufnr] -- current runner
	if not only_show then
		r:kill_all_processes()
		r:run_testcases(tctbl, compile)
	end
	r:set_restore_winid(api.nvim_get_current_win())
	r:show_ui(not only_show)
end

---Receive testcases, problems, contests or receive persistently from Competitive Companion
---@param mode "testcases" | "problem" | "contest" | "persistently" | "status" | "stop"
function M.receive(mode)
	local receive = require("competitest.receive")
	local error = nil
	if mode == "stop" then
		receive.stop_receiving()
	elseif mode == "status" then
		receive.show_status()
	elseif mode == "testcases" then
		local bufnr = api.nvim_get_current_buf()
		config.load_buffer_config(bufnr)
		local bufcfg = config.get_buffer_config(bufnr)
		local notify = bufcfg.receive_print_message
		error = receive.start_receiving("testcases", bufcfg.companion_port, notify, notify, bufnr, bufcfg)
	elseif mode == "problem" or mode == "contest" or mode == "persistently" then
		local cfg = config.load_local_config_and_extend(vim.fn.getcwd())
		local notify = cfg.receive_print_message
		---@diagnostic disable-next-line: param-type-mismatch
		error = receive.start_receiving(mode, cfg.companion_port, notify, notify, nil, cfg)
	else
		error = "unrecognized mode '" .. tostring(mode) .. "'"
	end

	if error then
		utils.notify("receive: " .. error .. ".")
	end
end

---Submit current solution via CPH Submit browser extension
---@param custom_url string? problem URL or Codeforces problem ID
function M.submit_solution(custom_url)
	local bufnr = api.nvim_get_current_buf()
	local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local source_code = table.concat(lines, "\n")
	local fname = api.nvim_buf_get_name(bufnr)
	local fext = vim.fn.fnamemodify(fname, ":e")

	local url = custom_url
	if not url or url == "" then
		-- 1. Look for explicit URL comment in buffer
		for _, line in ipairs(lines) do
			local match = string.match(line, "https?://[^%s%)]+")
			if match then
				url = match
				break
			end
		end
	end

	if not url or url == "" then
		-- 2. Infer from file directory or filename (e.g. /1900/C.cpp, /1900/C/sol.cpp, 1900C.cpp)
		local parent_dir = vim.fn.fnamemodify(fname, ":h:t")
		local stem = vim.fn.fnamemodify(fname, ":t:r")
		local contest, prob = string.match(parent_dir, "^(%d+)$"), string.match(stem, "^(%a+)$")
		if not (contest and prob) then
			contest, prob = string.match(stem, "^(%d+)[_%-]?([%a]%d*)$")
		end
		if contest and prob then
			url = string.format("https://codeforces.com/contest/%s/problem/%s", contest, string.upper(prob))
		end
	end

	local function queue_submission(final_url)
		if not final_url or final_url == "" then
			utils.notify("Submit canceled: Problem URL is required.", "WARN")
			return
		end

		if not string.match(final_url, "^https?://") then
			local contest, prob = string.match(final_url, "^(%d+)[/%-_]?(%a+)$")
			if contest and prob then
				final_url = string.format("https://codeforces.com/contest/%s/problem/%s", contest, string.upper(prob))
			end
		end

		local lang_map = {
			cpp = 89,       -- GNU G++23 64-bit (GCC 14.2, C++20/C++23)
			c = 43,         -- GNU GCC C11
			py = 31,        -- Python 3
			python = 31,    -- Python 3
			pypy = 41,      -- PyPy 3
			java = 74,      -- Java 17
			rs = 75,        -- Rust 2021
			rust = 75,      -- Rust 2021
		}
		local lang_id = lang_map[fext] or 89

		local prob_code = string.match(final_url, "/problem/([%w_]+)") or string.match(final_url, "%d+[/%-_](%a+)") or "A"
		prob_code = string.upper(prob_code)

		local receive_module = require("competitest.receive")
		receive_module.pending_submission_time = os.time()
		receive_module.pending_submission = {
			empty = false,
			problemName = prob_code,
			problemCode = prob_code,
			problemIndex = prob_code,
			url = final_url,
			problemUrl = final_url,
			sourceCode = source_code,
			code = source_code,
			languageId = lang_id,
		}

		if not receive_module.is_receiving() then
			M.receive("persistently")
		end

		local function get_submit_url(url_str)
			if not url_str or url_str == "" then return url_str end
			local contest_id, problem_id = string.match(url_str, "codeforces%.com/contest/(%d+)/problem/([%w_]+)")
			if contest_id and problem_id then
				return string.format("https://codeforces.com/contest/%s/submit", contest_id)
			end
			if string.find(url_str, "codeforces%.com/problemset/problem/") then
				return "https://codeforces.com/problemset/submit"
			end
			local gym_id = string.match(url_str, "codeforces%.com/gym/(%d+)/problem/")
			if gym_id then
				return string.format("https://codeforces.com/gym/%s/submit", gym_id)
			end
			return url_str
		end

		utils.notify("CPH Submit: Solution queued for " .. final_url .. "!\nWaiting for CPH Submit extension to process submission...", "INFO")
	end

	if not url or url == "" then
		vim.ui.input({ prompt = "Enter Problem URL or Codeforces ID (e.g. 1900/C): " }, function(input)
			if input then
				queue_submission(vim.trim(input))
			end
		end)
	else
		queue_submission(url)
	end
end

return M
