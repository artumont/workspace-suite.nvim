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

    -- Reset Neovim buffers and tab pages
    vim.cmd("silent %bwipeout!")
    while #vim.api.nvim_list_tabpages() > 1 do
      vim.cmd("tabclose")
    end
  end)

  after_each(function()
    -- Cleanup files and directory
    vim.fn.delete(temp_dir, "rf")
    vim.cmd("silent %bwipeout!")
    while #vim.api.nvim_list_tabpages() > 1 do
      vim.cmd("tabclose")
    end
  end)

  it("should collect, save, and restore buffer session details with tabs and layouts", function()
    -- 1. Create first tabpage, set tcd, open file1.txt
    local tcd1 = temp_dir .. "/dir1"
    vim.fn.mkdir(tcd1, "p")
    vim.cmd("tcd " .. vim.fn.fnameescape(tcd1))
    vim.cmd("edit " .. vim.fn.fnameescape(file1))
    vim.api.nvim_win_set_cursor(0, { 2, 2 })

    -- 2. Create second tabpage, set tcd, split layout, open file2.txt twice in splits
    vim.cmd("tabnew")
    local tcd2 = temp_dir .. "/dir2"
    vim.fn.mkdir(tcd2, "p")
    vim.cmd("tcd " .. vim.fn.fnameescape(tcd2))
    vim.cmd("edit " .. vim.fn.fnameescape(file2))
    vim.api.nvim_win_set_cursor(0, { 3, 1 })
    vim.cmd("split")

    -- Collect and save session
    local collected = session.collect()
    assert.are.equal(2, #collected.tabs)

    -- Tab 1 verification
    assert.are.equal(tcd1, collected.tabs[1].tcd)
    assert.is_not_nil(collected.tabs[1].layout)

    -- Tab 2 verification
    assert.are.equal(tcd2, collected.tabs[2].tcd)
    assert.are.equal("col", collected.tabs[2].layout[1]) -- horizontal split

    -- Save to file
    local save_ok = session.save(temp_dir)
    assert.is_true(save_ok)

    -- Wipe out Neovim state
    vim.cmd("silent %bwipeout!")
    while #vim.api.nvim_list_tabpages() > 1 do
      vim.cmd("tabclose")
    end

    -- Load session
    local load_ok = session.load(temp_dir)
    assert.is_true(load_ok)

    -- Verify restored tabs
    local tabpages = vim.api.nvim_list_tabpages()
    assert.are.equal(2, #tabpages)

    -- Verify tcd restored
    local cwd1 = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpages[1]))
    local cwd2 = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpages[2]))
    assert.are.equal(tcd1, vim.fn.fnamemodify(cwd1, ":p"):gsub("/$", ""))
    assert.are.equal(tcd2, vim.fn.fnamemodify(cwd2, ":p"):gsub("/$", ""))

    -- Clean up session file
    session.delete(temp_dir)
  end)
end)
