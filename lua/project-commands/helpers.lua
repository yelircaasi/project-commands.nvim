local M = {}

-- enum
M.direction = {
	edit = "edit",
    right = "right",
    left = "left",
    below = "below",
    above = "above",
    tab = "tab",
}

function M.validate_direction(self, direction)
	local d = self.direction[direction]
    if d == nil then
		vim.notify("nvim_commands: invalid direction: " .. d, vim.log.levels.ERROR)
		-- assert(command, "invalid direction: " .. direction)
	end
	return d
end

function M.read_json_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil, "Could not open file: " .. path
	end

	local content = file:read("*a")
	file:close()

	local ok, data = pcall(vim.fn.json_decode, content)
	if not ok then
		return nil, "Invalid JSON in " .. path .. ": " .. tostring(data)
	end

	return data, nil
end

-- Interpolate variables like ${file}, ${command}
function M.interpolate_variables(str, context)
	if not str then
		return str
	end

	return (str:gsub("%${(%w+)}", function(key)
		return context[key] or "${" .. key .. "}"
	end))
end

-- Find loaded buffer containing file, if it is open; otherwise nil
function M.find_buffer_for_file(filepath)
  local path = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)

      if name ~= "" then
        name = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))

        if name == path then
          return bufnr
        end
      end
    end
  end

  return nil
end

function M.ensure_dir_exists(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

-- Find project root, given root markers provided
function M.find_root(markers)
	local cwd = vim.fn.getcwd()
	local path = cwd

	while path ~= "/" and path ~= "" do
		for _, marker in ipairs(markers) do
			if vim.fn.filereadable(path .. "/" .. marker) == 1 or vim.fn.isdirectory(path .. "/" .. marker) == 1 then
				return path
			end
		end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then
			break
		end
		path = parent
	end

	return cwd
end

function M.merge_opts(old, new)
	return vim.tbl_deep_extend("force", old, new or {})
end

-- Convert a string like "cargo-check", "cargo_check" or "CargoCheck" into a PascalCase user command name (e.g. "CargoCheck")
function M.to_pascal_case(str)
	if not str or str == "" then
		return nil
	end

	-- Already PascalCase
	if str:match("^%u[%w]*$") then
		return str
	end

	-- Split on non-alphanumeric separators and capitalize each segment
	local parts = {}
	for seg in str:gmatch("[%w]+") do
		parts[#parts + 1] = seg:sub(1, 1):upper() .. seg:sub(2)
	end

	if #parts == 0 then
		return nil
	end
	return table.concat(parts)
end

return M
