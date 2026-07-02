---@module workspace-suite.session
--- Session save / restore for workspace-suite.nvim
--- Restores buffers, tabs, split layouts, and active panels.

local utils = require("workspace-suite.utils")

local M = {}

-- Supported panel commands by filetype
local PANEL_COMMANDS = {
  ["neo-tree"] = "Neotree filesystem show left",
  ["NvimTree"] = "NvimTreeOpen",
  ["aerial"] = "AerialOpen",
  ["Outline"] = "SymbolsOutline",
  ["undotree"] = "UndotreeShow",
}

--- Detect panel command from a window's buffer properties
---@param win number Window ID
---@return string|nil command The Neovim command to open the panel
local function detect_panel(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  local name = vim.api.nvim_buf_get_name(buf)

  if ft == "neo-tree" then
    if name:match("git_status") then
      return "Neotree git_status show right"
    elseif name:match("buffers") then
      return "Neotree buffers show float"
    else
      return "Neotree filesystem show left"
    end
  else
    return PANEL_COMMANDS[ft]
  end
end

--- Recursively serialize window layout
---@param layout table Nested layout from winlayout()
---@param win_to_data table Map of window ID to buffer data
---@return table serialized Serialized layout tree
local function serialize_layout(layout, win_to_data)
  local type = layout[1]
  if type == "leaf" then
    local win_id = layout[2]
    local win_data = win_to_data[win_id]
    return { "leaf", win_data }
  else
    local children = {}
    for _, child in ipairs(layout[2]) do
      table.insert(children, serialize_layout(child, win_to_data))
    end
    return { type, children }
  end
end

--- Recursively prune empty leaves from layout tree
---@param layout table
---@return table|nil pruned
local function prune_layout(layout)
  local type = layout[1]
  if type == "leaf" then
    if layout[2] == nil then
      return nil
    else
      return layout
    end
  else
    local children = {}
    for _, child in ipairs(layout[2]) do
      local pruned_child = prune_layout(child)
      if pruned_child then
        table.insert(children, pruned_child)
      end
    end
    if #children == 0 then
      return nil
    elseif #children == 1 then
      return children[1]
    else
      return { type, children }
    end
  end
end

--- Recursively restore split layout
---@param layout table
local function restore_layout(layout)
  local type = layout[1]
  if type == "leaf" then
    local win_data = layout[2]
    if win_data and win_data.file and vim.fn.filereadable(win_data.file) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(win_data.file))
      pcall(vim.api.nvim_win_set_cursor, 0, win_data.cursor)
    end
  else
    local children = layout[2]
    for i, child in ipairs(children) do
      if i > 1 then
        if type == "row" then
          vim.cmd("rightbelow vsplit")
        else
          vim.cmd("rightbelow split")
        end
      end
      restore_layout(child)
    end
  end
end

--- Collect the current session state: tabs, window layouts, and open panels.
---@return table session Serialisable session data
function M.collect()
  local tabs = {}
  local loaded_buffers = {}
  local tabpages = vim.api.nvim_list_tabpages()

  for _, tabpage in ipairs(tabpages) do
    local tab_number = vim.api.nvim_tabpage_get_number(tabpage)
    local tab_cwd = vim.fn.getcwd(-1, tab_number)
    tab_cwd = vim.fn.fnamemodify(tab_cwd, ":p"):gsub("/$", "")

    local win_to_data = {}
    local panels = {}
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)

    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      local buftype = vim.bo[buf].buftype

      local panel_cmd = detect_panel(win)
      if panel_cmd then
        table.insert(panels, panel_cmd)
      end

      if name ~= "" and buftype == "" and vim.fn.filereadable(name) == 1 then
        win_to_data[win] = {
          file = name,
          cursor = vim.api.nvim_win_get_cursor(win),
        }
        loaded_buffers[name] = true
      end
    end

    local raw_layout = vim.fn.winlayout(tab_number)
    local serialized = serialize_layout(raw_layout, win_to_data)
    local pruned = prune_layout(serialized)

    table.insert(tabs, {
      tcd = tab_cwd,
      layout = pruned,
      panels = panels,
    })
  end

  -- Track background buffers (loaded but not active in any window)
  local background_buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.bo[buf].buftype == "" and vim.fn.filereadable(name) == 1 then
        if not loaded_buffers[name] then
          table.insert(background_buffers, name)
        end
      end
    end
  end

  return {
    version = 2,
    cwd = vim.fn.getcwd(),
    tabs = tabs,
    buffers = background_buffers,
  }
end

--- Save the current session to disk.
---@param workspace_file string The absolute path to the .code-workspace file
---@return boolean ok
function M.save(workspace_file)
  local session_data = M.collect()
  if #session_data.tabs == 0 then
    return true
  end

  local filepath = utils.session_file(workspace_file)
  local ok, err = utils.write_json(filepath, session_data)
  if not ok then
    vim.notify("[workspace-suite] session save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Restore a session from disk.
---@param workspace_file string The absolute path to the .code-workspace file
---@return boolean ok Whether any buffers were restored
function M.load(workspace_file)
  local filepath = utils.session_file(workspace_file)
  local data, err = utils.read_json(filepath)
  if not data then
    return false
  end

  if data.version == 1 then
    return M._load_v1(data)
  end

  if not data.tabs or #data.tabs == 0 then
    return false
  end

  -- Create a clean scratch tab to begin wiping other tabs
  vim.cmd("tabnew")
  local temp_tab = vim.api.nvim_get_current_tabpage()
  local temp_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, temp_buf)
  vim.bo[temp_buf].buftype = "nofile"
  vim.bo[temp_buf].bufhidden = "wipe"

  -- Close all other tabpages
  local all_tabs = vim.api.nvim_list_tabpages()
  for _, t in ipairs(all_tabs) do
    if t ~= temp_tab then
      pcall(vim.api.nvim_cmd, { cmd = "tabclose", args = { tostring(vim.api.nvim_tabpage_get_number(t)) } }, {})
    end
  end

  -- Pre-load background buffers
  if data.buffers then
    for _, path in ipairs(data.buffers) do
      if vim.fn.filereadable(path) == 1 then
        local buf = vim.fn.bufadd(path)
        vim.bo[buf].buflisted = true
      end
    end
  end

  -- Restore tabs, layouts, and panels
  local restored_count = 0
  for idx, tab_data in ipairs(data.tabs) do
    if idx == 1 then
      if tab_data.tcd and vim.fn.isdirectory(tab_data.tcd) == 1 then
        vim.cmd("tcd " .. vim.fn.fnameescape(tab_data.tcd))
      end
    else
      vim.cmd("tabnew")
      if tab_data.tcd and vim.fn.isdirectory(tab_data.tcd) == 1 then
        vim.cmd("tcd " .. vim.fn.fnameescape(tab_data.tcd))
      end
    end

    if tab_data.layout then
      restore_layout(tab_data.layout)
    else
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, scratch)
      vim.bo[scratch].buftype = "nofile"
      vim.bo[scratch].bufhidden = "wipe"
    end

    if tab_data.panels then
      for _, cmd in ipairs(tab_data.panels) do
        pcall(vim.cmd, cmd)
      end
    end

    restored_count = restored_count + 1
  end

  vim.notify(
    ("[workspace-suite] restored %d tabpage%s"):format(restored_count, restored_count == 1 and "" or "s"),
    vim.log.levels.INFO
  )
  return true
end

--- Fallback loader for version 1 session format
---@param data table
---@return boolean ok
function M._load_v1(data)
  local restored = 0
  for _, entry in ipairs(data.buffers) do
    if vim.fn.filereadable(entry.path) == 1 then
      local buf = vim.fn.bufadd(entry.path)
      vim.bo[buf].buflisted = true
      vim.fn.bufload(buf)
      if restored == 0 then
        vim.api.nvim_win_set_buf(0, buf)
      end
      if entry.cursor then
        local line_count = vim.api.nvim_buf_line_count(buf)
        local row = math.min(entry.cursor[1], line_count)
        local col = entry.cursor[2] or 0
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == buf then
            pcall(vim.api.nvim_win_set_cursor, win, { row, col })
            break
          end
        end
      end
      restored = restored + 1
    end
  end
  return restored > 0
end

--- Delete session data for a workspace.
---@param workspace_file string
function M.delete(workspace_file)
  local filepath = utils.session_file(workspace_file)
  os.remove(filepath)
end

return M
