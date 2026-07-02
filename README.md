# workspace-suite.nvim

Manage everything workspace related and keep your projects contained and persistent.

## Requirements

- Neovim ≥ 0.9
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) _(optional — falls back to `vim.ui.select`)_
- `fd` or `find` on `$PATH` for workspace file discovery

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "artumont/workspace-suite.nvim",
  config = function()
    require("workspace-suite").setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "artumont/workspace-suite.nvim",
  config = function()
    require("workspace-suite").setup()
  end,
}
```

## Features

- **Create** `.code-workspace` files interactively or by importing from currently open tabs
- **Open** workspace files with a Telescope picker (or `vim.ui.select` fallback) — multi-select folders, open all, or open one
- **Sessions** — auto-save and auto-load buffer lists (+ cursor positions) when a workspace file exists at the project root

## Configuration

All options shown below are the defaults:

```lua
require("workspace-suite").setup({
  keys = {
    toggle_select = "<Tab>",   -- toggle multi-select in folder picker
    confirm       = "<CR>",    -- confirm / open selected folders
    select_all    = "<C-a>",   -- select all folders and open
  },
  session = {
    auto_save = true,   -- save buffer session on VimLeavePre (only if workspace file exists)
    auto_load = true,   -- restore buffer session on VimEnter (only if workspace file exists and no args)
  },
  -- Override this to run custom logic after each tab is created during workspace open.
  -- For example, to open Neo-tree:
  --   open_tab_callback = function(entry)
  --     vim.cmd("Neotree filesystem show left")
  --   end,
  open_tab_callback = nil,
})
```

## Commands

| Command                  | Description                                                        |
| ------------------------ | ------------------------------------------------------------------ |
| `:WorkspaceCreate`       | Create a `.code-workspace` file (import from tabs or add manually) |
| `:WorkspaceOpen`         | Discover and open a workspace file, pick folders to open as tabs   |
| `:WorkspaceSessionSave`  | Manually save the current buffer session                           |
| `:WorkspaceSessionLoad`  | Manually load a saved buffer session                               |
| `:WorkspaceSessionDelete`| Delete the saved session for this workspace root                   |