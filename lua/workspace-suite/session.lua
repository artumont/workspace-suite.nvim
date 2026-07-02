---@module workspace-suite.session
--- Session save / restore for workspace-suite.nvim
--- Only restores buffers and their cursor positions — no plugins, no options.

local utils = require("workspace-suite.utils")

local M = {}

--- Collect the current session state: all listed file-backed buffers
--- along with their cursor positions.
---@return table session Serialisable session data
function M.collect()
  local buffers = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      -- Only persist real files (skip nofile, terminal, plugin buffers, etc.)
      if name ~= "" and vim.bo[buf].buftype == "" and vim.fn.filereadable(name) == 1 then
        local cursor = { 1, 0 }
        -- Find a window displaying this buffer to grab cursor
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == buf then
            cursor = vim.api.nvim_win_get_cursor(win)
            break
          end
        end
        table.insert(buffers, {
          path = name,
          cursor = cursor,
        })
      end
    end
  end

  return {
    version = 1,
    cwd = vim.fn.getcwd(),
    buffers = buffers,
  }
end

--- Save the current session to disk.
---@param root string The project root where workspace file lives
---@return boolean ok
function M.save(root)
  local session = M.collect()
  if #session.buffers == 0 then
    return true -- nothing to save
  end

  local filepath = utils.session_file(root)
  utils.ensure_dir(utils.session_dir(root))

  local ok, err = utils.write_json(filepath, session)
  if not ok then
    vim.notify("[workspace-suite] session save failed: " .. (err or "unknown"), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Restore a session from disk.
---@param root string The project root
---@return boolean ok Whether any buffers were restored
function M.load(root)
  local filepath = utils.session_file(root)
  local data, err = utils.read_json(filepath)
  if not data then
    -- No session file is not an error
    return false
  end

  if not data.buffers or #data.buffers == 0 then
    return false
  end

  local restored = 0

  for _, entry in ipairs(data.buffers) do
    if vim.fn.filereadable(entry.path) == 1 then
      -- Open the buffer silently
      local buf = vim.fn.bufadd(entry.path)
      vim.bo[buf].buflisted = true
      vim.fn.bufload(buf)

      -- Restore the first buffer into the current window so the user
      -- sees something immediately
      if restored == 0 then
        vim.api.nvim_win_set_buf(0, buf)
      end

      -- Set cursor position if valid
      if entry.cursor then
        local line_count = vim.api.nvim_buf_line_count(buf)
        local row = math.min(entry.cursor[1], line_count)
        local col = entry.cursor[2] or 0

        -- Set cursor in the window that has this buffer
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

  if restored > 0 then
    vim.notify(
      ("[workspace-suite] restored %d buffer%s"):format(restored, restored == 1 and "" or "s"),
      vim.log.levels.INFO
    )
  end
  return restored > 0
end

--- Delete session data for a root.
---@param root string
function M.delete(root)
  local filepath = utils.session_file(root)
  os.remove(filepath)
end

return M
