# workspace-suite.nvim

Manage everything workspace related and keep your projects contained and persistent.

## Features

- **Create** `.code-workspace` files interactively or by importing from currently open tabs
- **Open** workspace files with a Telescope picker (or `vim.ui.select` fallback) — multi-select folders, open all, or open one
- **Sessions** — auto-save and auto-load buffer lists (+ cursor positions) when a workspace file exists at the project root

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

## How To Use

### Workspace Creation

`:WorkspaceCreate` presents two options:

1. **Import from open tabs** — each tab's working directory (`tcd`) becomes a workspace folder
2. **Add folders manually** — enter directory paths one at a time (with `<Tab>` completion)

The result is a standard `.code-workspace` JSON file with relative paths, fully compatible with VS Code.

### Workspace Open

`:WorkspaceOpen` searches for `.code-workspace` files (up to depth 5) starting from the git root (or cwd). If multiple workspace files are found, you pick one first. Then a Telescope picker shows the folders:

- **`<Tab>`** — toggle multi-select on individual folders
- **`<CR>`** — open the selected folder(s) as new tabs with `tcd` set
- **`<C-a>`** — open **all** folders at once

Each key is customisable via `setup()`.

### Sessions

When a `.code-workspace` file exists at the project root:

- **On exit** (`VimLeavePre`): the list of open file-backed buffers and their cursor positions is saved to `.nvim/sessions/session.json`
- **On enter** (`VimEnter`, no args): the session is restored — only buffers, nothing else (no plugin windows, no options, no splits)

The session directory (`.nvim/sessions/`) can be added to `.gitignore`.

## Project Root Detection

The plugin tries to detect the project root in this order:

1. **Git root** — `git rev-parse --show-toplevel`
2. **Current working directory** — fallback
