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

---Unload a runner (called on `BufUnload`)
---@param bufnr integer
function M.remove_runner(bufnr)
	M.runners[bufnr] = nil
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

	if not M.runners[bufnr] then -- no runner is associated to buffer
		M.runners[bufnr] = require("competitest.runner"):new(api.nvim_get_current_buf())
		if not M.runners[bufnr] then -- an error occurred
			return
		end
		-- remove runner data when buffer is unloaded
		api.nvim_command("autocmd BufUnload <buffer=" .. bufnr .. "> lua require('competitest.commands').remove_runner(vim.fn.expand('<abuf>'))")
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
		for _, line in ipairs(lines) do
			local match = string.match(line, "https?://[^%s%)]+")
			if match then
				url = match
				break
			end
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
			cpp = "cpp.g++20",
			c = "c.gcc11",
			py = "python3",
			python = "python3",
			java = "java",
			rs = "rust",
		}
		local lang = lang_map[fext] or "cpp.g++20"

		local prob_code = string.match(final_url, "/problem/([%w_]+)") or string.match(final_url, "%d+[/%-_](%a+)") or "A"
		prob_code = string.upper(prob_code)

		local receive_module = require("competitest.receive")
		receive_module.pending_submission = {
			empty = false,
			url = final_url,
			problemUrl = final_url,
			problemCode = prob_code,
			problem = prob_code,
			problemIndex = prob_code,
			sourceCode = source_code,
			code = source_code,
			languageId = lang,
			language = lang,
		}

		if not receive_module.receiver then
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

		local submit_url = get_submit_url(final_url)

		-- Automatically open submit page URL in browser so cph-submit extension activates and submits
		if vim.ui and vim.ui.open then
			pcall(vim.ui.open, submit_url)
		else
			pcall(vim.fn.jobstart, { "xdg-open", submit_url })
		end

		utils.notify("CPH Submit: Solution queued for " .. final_url .. "!\nOpening submit page in browser...", "INFO")
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
