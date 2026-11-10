-- Neovim plugin for running project-specific commands and displaying/editing their output

local utils = require("project-commands.helpers")
local domain = require("project-commands.domain")
local run_command = domain.run_command

local default_config = {
	commands_files = {
		"nvim-commands.lua",
		"nvim-commands.json",
		"commands.lua",
		"project-commands.lua",
		"project-commands.json",
	},
	keybind_prefix = "<leader>c",
	autoload = true,
	create_keybinds = true,
	create_user_commands = true,
	create_autocommands = true,
	root_markers = {
		".git",
		"package.json",
		"Cargo.toml",
		"go.mod",
		"pyproject.toml",
		"Makefile",
		"Justfile",
		"Taskfile.yml",
		"Taskfile.yaml",
		"nvim-commands.json",
		"nvim-commands.lua",
	},
	keybinds = {
		open_prefix = "<leader>o",
		open = {
			left = "h",
			below = "j",
			above = "k",
			right = "l",
			here = "o",
			tab = "t",
		},
	},
}

local M = {}

M.register_keybinds = function()
	local open_prefix = M.config.keybinds.open_prefix
	local keybinds = M.config.keybinds

	vim.keymap.set("n", open_prefix .. keybinds.open.tab, function()
		M.open_path_under_cursor(utils.direction.tab)
	end, { desc = "Open path under cursor in a new tab." })

	vim.keymap.set("n", open_prefix .. keybinds.open.here, function()
		M.open_path_under_cursor(utils.direction.edit)
	end, { desc = "Open path under cursor to the edit." })

	vim.keymap.set("n", open_prefix .. keybinds.open.left, function()
		M.open_path_under_cursor(utils.direction.left)
	end, { desc = "Open path under cursor to the left." })

	vim.keymap.set("n", open_prefix .. keybinds.open.below, function()
		M.open_path_under_cursor(utils.direction.below)
	end, { desc = "Open path under cursor to the below." })

	vim.keymap.set("n", open_prefix .. keybinds.open.above, function()
		M.open_path_under_cursor(utils.direction.above)
	end, { desc = "Open path under cursor to the above." })

	vim.keymap.set("n", open_prefix .. keybinds.open.right, function()
		M.open_path_under_cursor(utils.direction.right)
	end, { desc = "Open path under cursor to the right." })

	if M.loaded_commands == nil then
		return
	end

	for i, cmd in ipairs(M.loaded_commands) do
		local suffix = cmd.command_name
		if not suffix or suffix == "" or suffix == "null" then
			suffix = tostring(i)
		end

		local keybind = M.config.keybind_prefix .. suffix

		-- Keybind is <prefix><key_suffix> if command_name is set, otherwise <prefix><index>
		-- TODO: infer better fallback
		vim.keymap.set(
			"n",
			keybind,
			utils.as_function(cmd, run_command),
			{ desc = "Run: " .. (cmd.name or ("command " .. i)), silent = true }
		)
	end
end

M.register_project_user_commands = function()
	-- command_name "CargoCheck" => :CargoCheck
	-- command_name "cargo-check" also normalizes to :CargoCheck
	-- If command_name is missing/null, falls back to :NvimCommand<index>
	-- TODO: infer better fallback

	if M.loaded_commands == nil then
		return
	end

	for i, cmd in ipairs(M.loaded_commands) do
		local raw_name = cmd.command_name
		local user_cmd_name

		if raw_name and raw_name ~= "" and raw_name ~= "null" then
			user_cmd_name = utils.to_pascal_case(raw_name)
		end

		if not user_cmd_name then
			user_cmd_name = "NvimCommand" .. i
		end

		-- Remove existing command if any (so reload picks up changes)
		pcall(vim.api.nvim_del_user_command, user_cmd_name)

		local ok, err = pcall(vim.api.nvim_create_user_command, user_cmd_name, function()
			run_command(cmd)
		end, { desc = "Run: " .. (cmd.name or ("command " .. i)) })

		if not ok then
			vim.notify(
				"nvim_commands: could not register :" .. user_cmd_name .. " — " .. tostring(err),
				vim.log.levels.WARN
			)
		end
	end
end

M.find_and_read_file = function()
	for _, filename in ipairs(M.config.commands_files) do
		local root = utils.find_root(M.config.root_markers)
		local commands_path = root .. "/" .. filename
		if utils.endswith(commands_path, ".lua") then
			M.commands_file = commands_path
			return utils.read_lua_file(commands_path), nil
		else
			if utils.endswith(commands_path, ".json") then
				M.commands_file = commands_path
				return utils.read_json_file(commands_path), nil
			end
		end
		return nil, "No valid file (.lua or .json) found."
	end
end

-- Load commands from the in-project commands file
--     (default: nvim-commands.lua|nvim-commands.json)
M.load = function()
	M:find_and_read_file()

	if vim.fn.filereadable(M.commands_file) == 0 then
		print("No file found: " .. tostring(M.commands_file))
		return
	end

	local data, err = M.find_and_read_file()
	if not data then
		vim.notify("nvim_commands: " .. err, vim.log.levels.ERROR)
		return
	end

	if not data.commands or type(data.commands) ~= "table" then
		vim.notify("nvim_commands: no 'commands' array in " .. config_path, vim.log.levels.ERROR)
	end

	M.loaded_commands = data.commands or {}
	print(vim.inspect(M.loaded_commands))
end

M.register_universal_user_commands = function()
	vim.api.nvim_create_user_command("NvimCommandsReload", function()
		M:load()
		vim.notify("Reloaded nvim_commands from config", vim.log.levels.INFO)
	end, { desc = "Reload nvim_commands config" })

	vim.api.nvim_create_user_command("NvimCommandsRun", function(opts)
		local name = opts.args
		for _, cmd in ipairs(M.loaded_commands) do
			if cmd.name == name then
				run_command(cmd)
				return
			end
		end
		vim.notify("No command named: " .. name, vim.log.levels.WARN)
	end, { nargs = 1, desc = "Run a named command entry: `:ProjectCommandsRun NAME`" })
end

M.register_autocommands = function()
	-- Reload when config file changes
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = M.commands_file,
		callback = function()
			M:load()
		end,
	})

	-- Try to load when entering a new directory
	vim.api.nvim_create_autocmd("DirChanged", {
		callback = function()
			M:load()
		end,
	})
end

function M.open_path_under_cursor(direction)
	local direction = utils:validate_direction(direction)
	local path = vim.fn.expand("<cfile>")
	path = vim.fn.expand(path)

	if not vim.startswith(path, "/") then
		path = vim.fs.joinpath(project_root, path)
	end

	path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	path = vim.fn.fnameescape(path)

	domain.open_file(path, direction)

	--   local bufnr = utils.find_buffer_for_file(path)

	--   local commands = {
	--     edit = "edit",
	--     right = "vsplit",
	--     left = "leftabove vsplit",
	--     below = "split",
	--     above = "above split",
	--     tab = "tabedit",
	--   }

	--   local command = commands[direction]

	--   if bufnr then
	--     vim.cmd(command)
	--     vim.api.nvim_win_set_buf(0, bufnr)
	--   else
	--     vim.cmd(command .. " " .. vim.fn.fnameescape(path))
	--   end
end

M.commands_file = nil

M.setup = function(opts)
	M.config = utils.merge_opts(default_config, opts)

	M.project_root = utils.find_root(M.config.root_markers)
	print("M.project_root: " .. M.project_root)

	if M.config.autoload then
		M:load()
	else
		M:find_and_read_file()
	end
	print("M.commands_file: " .. tostring(M.commands_file))

	if M.config.create_keybinds then
		M:register_keybinds()
	end

	if M.config.create_user_commands then
		M:register_universal_user_commands()
		M:register_project_user_commands()
	end

	if M.config.create_autocommands then
		M:register_autocommands()
	end
end

return M
