local session = require("workspace-suite.session")
local utils = require("workspace-suite.utils")

describe("session", function()
  local temp_dir
  local file1, file2

  before_each(function()
    -- Create temporary directory and files
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    file1 = temp_dir .. "/test1.txt"
    file2 = temp_dir .. "/test2.txt"

    -- Write some content to the files
    local f1 = io.open(file1, "w")
    f1:write("line 1\nline 2\nline 3\n")
    f1:close()

    local f2 = io.open(file2, "w")
    f2:write("apple\nbanana\ncherry\n")
    f2:close()

    -- Reset Neovim buffers
    vim.cmd("silent %bwipeout!")
  end)

  after_each(function()
    -- Cleanup files and directory
    vim.fn.delete(temp_dir, "rf")
    vim.cmd("silent %bwipeout!")
  end)

  it("should collect, save, and restore buffer session details", function()
    -- Open files in windows
    vim.cmd("edit " .. vim.fn.fnameescape(file1))
    vim.api.nvim_win_set_cursor(0, { 2, 2 }) -- Line 2, column 2

    vim.cmd("split")
    vim.cmd("edit " .. vim.fn.fnameescape(file2))
    vim.api.nvim_win_set_cursor(0, { 3, 1 }) -- Line 3, column 1

    -- Collect session state
    local collected = session.collect()
    assert.are.equal(2, #collected.buffers)

    -- Save session
    local save_ok = session.save(temp_dir)
    assert.is_true(save_ok)

    -- Verify session file exists and contains correct data
    local session_file = utils.session_file(temp_dir)
    assert.are.equal(1, vim.fn.filereadable(session_file))

    local saved_data = utils.read_json(session_file)
    assert.are.equal(1, saved_data.version)
    assert.are.equal(2, #saved_data.buffers)

    -- Close all buffers
    vim.cmd("silent %bwipeout!")

    -- Load session
    local load_ok = session.load(temp_dir)
    assert.is_true(load_ok)

    -- Verify buffers are restored and cursor positions are applied
    local loaded_bufs = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name ~= "" then
          loaded_bufs[name] = buf
        end
      end
    end

    assert.is_not_nil(loaded_bufs[file1])
    assert.is_not_nil(loaded_bufs[file2])

    -- Delete session
    session.delete(temp_dir)
    assert.are.equal(0, vim.fn.filereadable(session_file))
  end)
end)
