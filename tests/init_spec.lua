local ws = require("workspace-suite")

describe("workspace-suite init", function()
  before_each(function()
    -- reset config
    ws.config = {
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
  end)

  it("should merge setup options", function()
    ws.setup({
      keys = {
        confirm = "<leader>o",
      },
      session = {
        auto_save = false,
      }
    })

    assert.are.equal("<leader>o", ws.config.keys.confirm)
    assert.are.equal("<Tab>", ws.config.keys.toggle_select)
    assert.are.equal(false, ws.config.session.auto_save)
    assert.are.equal(true, ws.config.session.auto_load)
  end)

  it("should register user commands", function()
    ws.setup()
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.WorkspaceCreate)
    assert.is_not_nil(cmds.WorkspaceOpen)
    assert.is_not_nil(cmds.WorkspaceSessionSave)
    assert.is_not_nil(cmds.WorkspaceSessionLoad)
    assert.is_not_nil(cmds.WorkspaceSessionDelete)
  end)
end)
