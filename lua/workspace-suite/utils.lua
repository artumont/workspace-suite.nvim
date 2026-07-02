---@module workspace-suite.utils
--- Utility helpers for workspace-suite.nvim

local M = {}

--- Find the git root directory starting from `path`.
--- Falls back to `vim.fn.getcwd()` if no git root is found.
---@param path? string Starting directory (defaults to cwd)
---@return string root The git root or cwd
function M.find_root(path)
  path = path or vim.fn.getcwd()

  -- Try git root first
  local git_dir = vim.fn.systemlist("git -C " .. vim.fn.shellescape(path) .. " rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error == 0 and git_dir[1] and git_dir[1] ~= "" then
    return vim.fn.fnamemodify(git_dir[1], ":p"):gsub("/$", "")
  end

  return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

--- Discover `.code-workspace` files under `root` (max depth 5).
---@param root string Directory to search
---@return string[] paths List of absolute paths to workspace files
function M.find_workspace_files(root)
  local results = vim.fn.systemlist(
    "fd --type f --extension code-workspace --max-depth 5 . " .. vim.fn.shellescape(root)
  )

  if vim.v.shell_error ~= 0 or #results == 0 then
    results = vim.fn.systemlist(
      "find " .. vim.fn.shellescape(root) .. " -maxdepth 5 -name '*.code-workspace' 2>/dev/null"
    )
  end

  -- Normalise to absolute paths
  local out = {}
  for _, r in ipairs(results) do
    if r ~= "" then
      table.insert(out, vim.fn.fnamemodify(r, ":p"))
    end
  end
  return out
end

--- Make `target` relative to `base`.
---@param base string Base directory (absolute)
---@param target string Target path (absolute)
---@return string relative The relative path
function M.make_relative(base, target)
  base = base:gsub("/$", "")
  target = target:gsub("/$", "")
  if base == target then
    return "."
  end
  base = base .. "/"
  if target:sub(1, #base) == base then
    return target:sub(#base + 1)
  end
  return target
end


--- Read and JSON-decode a file.
---@param filepath string Absolute path to JSON file
---@return table|nil data Decoded table, or nil on failure
---@return string|nil err Error message on failure
function M.read_json(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open: " .. filepath
  end

  local content = file:read("*a")
  file:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    return nil, "Invalid JSON in: " .. filepath
  end

  return data
end

--- Write a table as pretty-printed JSON to a file.
---@param filepath string Absolute path to write
---@param data table Data to encode
---@return boolean ok
---@return string|nil err
function M.write_json(filepath, data)
  local encoded = vim.fn.json_encode(data)
  -- Pretty-print with python if available, otherwise write raw
  local pretty = vim.fn.system("echo " .. vim.fn.shellescape(encoded) .. " | python3 -m json.tool 2>/dev/null")
  if vim.v.shell_error ~= 0 or pretty == "" then
    pretty = encoded
  end

  local dir = vim.fn.fnamemodify(filepath, ":h")
  vim.fn.mkdir(dir, "p")

  local file = io.open(filepath, "w")
  if not file then
    return false, "Could not write: " .. filepath
  end
  file:write(pretty)
  file:close()
  return true
end

--- Ensure a directory exists.
---@param dir string
function M.ensure_dir(dir)
  vim.fn.mkdir(dir, "p")
end

--- Locate the active workspace file by looking upwards from the CWD.
---@param path? string Starting directory (defaults to cwd)
---@return string|nil workspace_file The absolute path to the workspace file, or nil
function M.find_active_workspace(path)
  path = path or vim.fn.getcwd()
  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")

  while path ~= "" and path ~= "/" do
    local files = vim.fn.globpath(path, "*.code-workspace", false, true)
    if #files > 0 then
      return vim.fn.fnamemodify(files[1], ":p")
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
  return nil
end

--- Get the centralized session file path for a workspace.
---@param workspace_file string The absolute path to the .code-workspace file
---@return string path Centralized session JSON file path
function M.session_file(workspace_file)
  local data_dir = vim.fn.stdpath("data") .. "/workspace-suite/sessions"
  local hash = vim.fn.sha256(workspace_file)
  local name = vim.fn.fnamemodify(workspace_file, ":t")
  return data_dir .. "/" .. name .. "_" .. hash .. ".json"
end

return M
