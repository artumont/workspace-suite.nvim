---@module workspace-suite
--- workspace-suite.nvim — VS Code-style workspace management for Neovim
---
--- Features:
---   • Create `.code-workspace` files interactively or from open tabs
---   • Open workspace files with a Telescope picker to choose folders
---   • Auto-save / auto-load buffer sessions per workspace root

local utils = require("workspace-suite.utils")
local session = require("workspace-suite.session")

local M = {}

---@class WorkspaceSuiteConfig
---@field keys WorkspaceSuiteKeys
---@field session WorkspaceSuiteSession
---@field open_tab_callback? fun(entry: {label: string, root: string}) Called after each tab is created during workspace open. Override to set up your own tree/sidebar.

---@class WorkspaceSuiteKeys
---@field toggle_select string Keymap in the picker to toggle multi-select (default "<Tab>")
---@field confirm string Keymap to confirm / open selected (default "<CR>")
---@field select_all string Keymap to select all and open (default "<C-a>")

---@class WorkspaceSuiteSession
---@field auto_save boolean Auto-save session on VimLeavePre (default true)
---@field auto_load boolean Auto-load session on VimEnter when workspace file exists (default true)

---@type WorkspaceSuiteConfig
M.config = {
  keys = {
    toggle_select = "<Tab>",
    confirm = "<CR>",
    select_all = "<C-a>",
  },
  session = {
    auto_save = true,
    auto_load = true,
  },
  open_tab_callback = nil,
}

-- ────────────────────────────────────────────────────────────────
-- Setup
-- ────────────────────────────────────────────────────────────────

--- Initialise the plugin.
---@param opts? table Partial config overrides
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register user commands
  vim.api.nvim_create_user_command("WorkspaceCreate", function()
    M.create_workspace()
  end, { desc = "Create a .code-workspace file from open tabs or interactively" })

  vim.api.nvim_create_user_command("WorkspaceOpen", function()
    M.open_workspace()
  end, { desc = "Open a .code-workspace file and pick folders" })

  vim.api.nvim_create_user_command("WorkspaceSessionSave", function()
    M.save_session()
  end, { desc = "Save the current buffer session" })

  vim.api.nvim_create_user_command("WorkspaceSessionLoad", function()
    M.load_session()
  end, { desc = "Load a saved buffer session" })

  vim.api.nvim_create_user_command("WorkspaceSessionDelete", function()
    M.delete_session()
  end, { desc = "Delete the saved session for this workspace" })

  -- Autocmds for auto-save / auto-load
  local augroup = vim.api.nvim_create_augroup("WorkspaceSuite", { clear = true })

  if M.config.session.auto_save then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = augroup,
      callback = function()
        local root = utils.find_root()
        local ws_files = utils.find_workspace_files(root)
        if #ws_files > 0 then
          session.save(root)
        end
      end,
    })
  end

  if M.config.session.auto_load then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = augroup,
      nested = true,
      callback = function()
        -- Only auto-load when Neovim was opened without file arguments
        if vim.fn.argc() > 0 then
          return
        end
        local root = utils.find_root()
        local ws_files = utils.find_workspace_files(root)
        if #ws_files > 0 then
          -- Defer so the UI is fully initialised
          vim.defer_fn(function()
            session.load(root)
          end, 50)
        end
      end,
    })
  end
end

-- ────────────────────────────────────────────────────────────────
-- Session API
-- ────────────────────────────────────────────────────────────────

--- Save the current buffer session.
---@param root? string Optional project root path (defaults to auto-detected root)
---@return boolean ok
function M.save_session(root)
  root = root or utils.find_root()
  local ok = session.save(root)
  if ok then
    vim.notify("[workspace-suite] session saved", vim.log.levels.INFO)
  end
  return ok
end

--- Load the saved buffer session.
---@param root? string Optional project root path (defaults to auto-detected root)
---@return boolean ok
function M.load_session(root)
  root = root or utils.find_root()
  local ok = session.load(root)
  if not ok then
    vim.notify("[workspace-suite] no session found", vim.log.levels.WARN)
  end
  return ok
end

--- Delete the saved buffer session.
---@param root? string Optional project root path (defaults to auto-detected root)
function M.delete_session(root)
  root = root or utils.find_root()
  session.delete(root)
  vim.notify("[workspace-suite] session deleted", vim.log.levels.INFO)
end

-- ────────────────────────────────────────────────────────────────
-- Create workspace
-- ────────────────────────────────────────────────────────────────

--- Gather folder information from currently open tabs.
--- Each tab's working directory (`tcd`) is treated as a workspace folder.
---@return table[] entries List of {label, root} tables
local function tabs_to_entries()
  local entries = {}
  local seen = {}

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    -- Get the tab-local directory (tcd). If no tcd was set, falls back to global cwd.
    local tab_cwd = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab))
    tab_cwd = vim.fn.fnamemodify(tab_cwd, ":p"):gsub("/$", "")

    if not seen[tab_cwd] then
      seen[tab_cwd] = true
      table.insert(entries, {
        label = vim.fn.fnamemodify(tab_cwd, ":t"),
        root = tab_cwd,
      })
    end
  end

  return entries
end

--- Create a `.code-workspace` file.
--- Offers to import from currently open tabs or add folders interactively.
function M.create_workspace()
  local root = utils.find_root()

  vim.ui.select({ "Import from open tabs", "Add folders manually" }, {
    prompt = "Workspace creation method:",
  }, function(choice)
    if not choice then
      return
    end

    if choice == "Import from open tabs" then
      M._create_from_tabs(root)
    else
      M._create_manually(root)
    end
  end)
end

--- Create workspace from open tabs.
---@param root string Project root
function M._create_from_tabs(root)
  local entries = tabs_to_entries()

  if #entries == 0 then
    vim.notify("[workspace-suite] no tabs with distinct directories found", vim.log.levels.WARN)
    return
  end

  -- Build the workspace data
  local folders = {}
  for _, e in ipairs(entries) do
    table.insert(folders, {
      name = e.label,
      path = utils.make_relative(root, e.root),
    })
  end

  -- Ask for filename
  vim.ui.input({
    prompt = "Workspace filename (relative to " .. root .. "): ",
    default = vim.fn.fnamemodify(root, ":t") .. ".code-workspace",
  }, function(name)
    if not name or name == "" then
      return
    end

    -- Ensure extension
    if not name:match("%.code%-workspace$") then
      name = name .. ".code-workspace"
    end

    local filepath = root .. "/" .. name
    local data = { folders = folders, settings = {} }
    local ok, err = utils.write_json(filepath, data)
    if ok then
      vim.notify("[workspace-suite] created " .. filepath, vim.log.levels.INFO)
    else
      vim.notify("[workspace-suite] " .. (err or "write failed"), vim.log.levels.ERROR)
    end
  end)
end

--- Create workspace by manually entering folder paths.
---@param root string Project root
function M._create_manually(root)
  local folders = {}

  local function ask_folder()
    vim.ui.input({
      prompt = ("Folder #%d (empty to finish): "):format(#folders + 1),
      completion = "dir",
    }, function(input)
      if not input or input == "" then
        if #folders == 0 then
          vim.notify("[workspace-suite] no folders added, aborting", vim.log.levels.WARN)
          return
        end
        -- Finished collecting; ask for filename
        M._finish_manual_create(root, folders)
        return
      end

      -- Resolve path
      local abs = vim.fn.fnamemodify(input, ":p"):gsub("/$", "")
      if vim.fn.isdirectory(abs) ~= 1 then
        vim.notify("[workspace-suite] not a directory: " .. abs, vim.log.levels.WARN)
      else
        table.insert(folders, {
          name = vim.fn.fnamemodify(abs, ":t"),
          path = utils.make_relative(root, abs),
        })
        vim.notify(("[workspace-suite] added: %s"):format(abs), vim.log.levels.INFO)
      end

      -- Ask for more
      vim.defer_fn(ask_folder, 50)
    end)
  end

  ask_folder()
end

--- Finish manual workspace creation by asking for a filename.
---@param root string
---@param folders table[]
function M._finish_manual_create(root, folders)
  vim.ui.input({
    prompt = "Workspace filename (relative to " .. root .. "): ",
    default = vim.fn.fnamemodify(root, ":t") .. ".code-workspace",
  }, function(name)
    if not name or name == "" then
      return
    end

    if not name:match("%.code%-workspace$") then
      name = name .. ".code-workspace"
    end

    local filepath = root .. "/" .. name
    local data = { folders = folders, settings = {} }
    local ok, err = utils.write_json(filepath, data)
    if ok then
      vim.notify("[workspace-suite] created " .. filepath, vim.log.levels.INFO)
    else
      vim.notify("[workspace-suite] " .. (err or "write failed"), vim.log.levels.ERROR)
    end
  end)
end

-- ────────────────────────────────────────────────────────────────
-- Open workspace
-- ────────────────────────────────────────────────────────────────

--- Parse a workspace file and return the list of valid folder entries.
---@param workspace_file string Absolute path to .code-workspace file
---@return table[]|nil entries List of {label, root}
local function parse_workspace(workspace_file)
  local data, err = utils.read_json(workspace_file)
  if not data then
    vim.notify("[workspace-suite] " .. (err or "read failed"), vim.log.levels.ERROR)
    return nil
  end

  if not data.folders then
    vim.notify("[workspace-suite] workspace has no 'folders' key", vim.log.levels.ERROR)
    return nil
  end

  local workspace_dir = vim.fn.fnamemodify(workspace_file, ":p:h")
  local entries = {}

  for _, folder in ipairs(data.folders) do
    local abs = vim.fn.fnamemodify(workspace_dir .. "/" .. folder.path, ":p"):gsub("/$", "")
    if vim.fn.isdirectory(abs) == 1 then
      table.insert(entries, {
        label = folder.name or vim.fn.fnamemodify(abs, ":t"),
        root = abs,
      })
    end
  end

  if #entries == 0 then
    vim.notify("[workspace-suite] no valid folders in workspace", vim.log.levels.WARN)
    return nil
  end

  return entries
end

--- Open selected folder entries as tabs.
---@param selected table[] List of {label, root}
local function open_tabs(selected)
  local callback = M.config.open_tab_callback

  local function open_next(i)
    if i > #selected then
      vim.cmd("tablast")
      return
    end

    local entry = selected[i]
    vim.cmd("tabnew")
    vim.cmd("tcd " .. vim.fn.fnameescape(entry.root))

    -- Create a scratch buffer so the tab isn't empty
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, entry.label .. " [" .. i .. "]")
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"

    if callback then
      callback(entry)
    end

    vim.defer_fn(function()
      open_next(i + 1)
    end, 100)
  end

  open_next(1)
end

--- Show a Telescope picker for workspace folder entries.
---@param entries table[] List of {label, root}
---@param title string Picker title
local function pick_folders(entries, title)
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    -- Fallback: vim.ui.select
    M._pick_folders_fallback(entries, title)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 24 },
      { remaining = true },
    },
  })

  local keys = M.config.keys

  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = function()
              return displayer({
                { entry.label, "TelescopeResultsIdentifier" },
                { entry.root, "TelescopeResultsComment" },
              })
            end,
            ordinal = entry.label,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        -- Default confirm: open multi-selected, or single selected
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selected = picker:get_multi_selection()
          if #selected == 0 then
            selected = { action_state.get_selected_entry() }
          end
          actions.close(prompt_bufnr)
          open_tabs(vim.tbl_map(function(e)
            return e.value
          end, selected))
        end)

        -- Select all and open
        map({ "i", "n" }, keys.select_all, function()
          actions.close(prompt_bufnr)
          open_tabs(entries)
        end)

        return true
      end,
    })
    :find()
end

--- Fallback folder picker using vim.ui.select when Telescope is not available.
---@param entries table[]
---@param title string
function M._pick_folders_fallback(entries, title)
  local labels = {}
  for _, e in ipairs(entries) do
    table.insert(labels, e.label .. "  (" .. e.root .. ")")
  end

  -- Add an "Open all" option at the top
  table.insert(labels, 1, "[ Open ALL folders ]")

  vim.ui.select(labels, { prompt = title }, function(_, idx)
    if not idx then
      return
    end

    if idx == 1 then
      -- Open all
      open_tabs(entries)
    else
      open_tabs({ entries[idx - 1] })
    end
  end)
end

--- Show a Telescope picker to choose a workspace file from a list.
---@param files string[] List of workspace file paths
---@param callback fun(file: string) Called with the chosen file
local function pick_workspace_file(files, callback)
  local has_telescope, _ = pcall(require, "telescope")
  if not has_telescope then
    local labels = {}
    for _, f in ipairs(files) do
      table.insert(labels, vim.fn.fnamemodify(f, ":~:."))
    end
    vim.ui.select(labels, { prompt = "Select workspace file" }, function(_, idx)
      if idx then
        callback(files[idx])
      end
    end)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Select Workspace File",
      finder = finders.new_table({
        results = files,
        entry_maker = function(entry)
          return {
            value = entry,
            display = vim.fn.fnamemodify(entry, ":~:."),
            ordinal = entry,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            callback(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Open a workspace: discover workspace files, pick one (if multiple), then
--- pick folders to open as tabs.
---@param workspace_file? string Optional direct path to a workspace file
function M.open_workspace(workspace_file)
  if workspace_file then
    local entries = parse_workspace(workspace_file)
    if entries then
      local title = "Select Folders — " .. vim.fn.fnamemodify(workspace_file, ":t")
      pick_folders(entries, title)
    end
    return
  end

  local root = utils.find_root()
  local files = utils.find_workspace_files(root)

  if #files == 0 then
    vim.notify("[workspace-suite] no .code-workspace files found", vim.log.levels.WARN)
    return
  end

  local function load(ws_file)
    local entries = parse_workspace(ws_file)
    if entries then
      local title = "Select Folders — " .. vim.fn.fnamemodify(ws_file, ":t")
      pick_folders(entries, title)
    end
  end

  if #files == 1 then
    load(files[1])
  else
    pick_workspace_file(files, load)
  end
end

return M
