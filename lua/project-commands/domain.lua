local utils = require("project-commands.helpers")

local success_icon = "✓ "
local failure_icon = "✗ "

M = {}

-- Open the output file in a split
function M.open_output_file(filepath, direction)
	local abs = vim.fn.fnamemodify(filepath, ":p")

	local existing = utils.find_buffer_for_file(abs)

	local split_cmd
	if direction == "left" then
		split_cmd = "topleft vsplit"
	elseif direction == "right" then
		split_cmd = "botright vsplit"
	elseif direction == "top" then
		split_cmd = "topleft split"
	elseif direction == "bottom" then
		split_cmd = "botright split"
	else
		split_cmd = "botright vsplit"
	end

	if existing then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == existing then
				vim.api.nvim_set_current_win(win)
				vim.cmd("edit!")
				return
			end
		end
	end

	vim.cmd(split_cmd .. " " .. vim.fn.fnameescape(abs))
end

-- Run a single command definition
function M.run_command(cmd_def, opts)
	opts = opts or {}

	local cwd = vim.fn.getcwd()
	local current_file = vim.api.nvim_buf_get_name(0)

	local context = {
		file = current_file,
		cwd = cwd,
		name = cmd_def.name or "",
		command = cmd_def.command or "",
	}

	local raw_command = utils.interpolate_variables(cmd_def.command or "", context)

	if raw_command == "" then
		vim.notify("No command specified for: " .. (cmd_def.name or "unnamed"), vim.log.levels.WARN)
		return
	end

	local output_file = utils.interpolate_variables(cmd_def.output_file or "", context)

	local shell_cmd = raw_command

	if output_file ~= "" then
		output_file = vim.fn.fnamemodify(output_file, ":p")
		utils.ensure_dir_exists(output_file)
		shell_cmd = shell_cmd .. " > " .. vim.fn.shellescape(output_file) .. " 2>&1"
	end

	vim.notify("Running: " .. (cmd_def.name or raw_command), vim.log.levels.INFO)

	vim.fn.jobstart(shell_cmd, {
		cwd = cwd,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify(success_icon .. (cmd_def.name or "command") .. " finished", vim.log.levels.INFO)
				else
					vim.notify(
						failure_icon .. (cmd_def.name or "command") .. " exited with " .. exit_code,
						vim.log.levels.WARN
					)
				end

				if cmd_def.auto_open and output_file ~= "" then
					M.open_output_file(output_file, cmd_def.split_direction or "right")
				end
			end)
		end,
	})
end

return M
