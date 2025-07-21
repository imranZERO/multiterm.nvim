
# Multiterm.nvim

Toggle and Switch Between Multiple Floating Terminals in Neovim.

## Introduction

Some plugins have already provided the functionality to create a floating terminal window in Neovim or Vim. But they only support one running instance, or they just cannot allow you to put the terminal session into background. And some of them are too complicated to use.

You might often need to open several terminal sessions in Vim. Let's suppose you need to create 2 terminal sessions, one for running tests and the other one for compiling. It is painful to switch between them as you have to switch between Vim modes and use tab or window switching commands.

With **Multiterm**, all these pains disappear. You could use one single command `:Multiterm` and mapping `<Plug>(Multiterm)` with **count** to **create**, **hide** and **display** the floating terminal window you want.

## Screenshot

Here's the `gitui` app running on Multiterm inside [Neovide](https://neovide.dev/):

[![Screenshot](https://i.postimg.cc/sXKHTwBB/gitui-in-multiterm.png)](https://postimg.cc/PppMxbQh)

## Prerequisites

**Multiterm.nvim** supports neovim versions `0.10.0` or later. Older versions also might work, no guarantees.

## Installation

If you use `lazy.nvim` as your plugin manager:

```lua
{
    "imranzero/multiterm.nvim",
    event = "VeryLazy",
    config = function()
        require("multiterm").setup({
            -- Recommended keymaps:
            vim.keymap.set({ "n", "v", "i", "t" }, "<F12>", "<Plug>(Multiterm)"),
            vim.keymap.set("n", "<leader><F12>", "<Plug>(MultitermList)"),
    
            -- Add configuration options here if needed
        })
    end
}
```

## Usage

If you do not have any floating terminal instance, run `:Multiterm [cmd]` will create a floating terminal with tag `1`. It is not suggested to run a non-interactive `cmd` as the terminal session will end and get destroyed as soon as `cmd` finishes if run `:Multiterm` without `!`.

If your cursor is in a floating terminal window, run `:Multiterm` will close that window and put the terminal session into background. Otherwise the **most recently used** floating terminal instance will be activated.

If you run `:3Multiterm` and do not have a floating terminal with tag `3` created, a new floating terminal window with tag `3` will be created and become the current active floating window.

If your tag `3` floating terminal is in the background, run `:3Multiterm` will put the session into foreground. You could then run `:Multiterm` to close the window and put it into background again.

## Commands & Mappings

A single command is provided:

```viml
:[count]Multiterm[!] [cmd]
```

- `[count]` could be a number between 1 and 9 and is the tag of the floating window that you want to activate. If it is not specified, the current active floating terminal session will be closed, or the tag `1` session will be activated in the condition that there is no active session.
- `[!]` forces the terminal window not to close when the terminal job exits. Otherwise, in NeoVim the window will be closed as immediately as the job exits with a zero exit code, and in Vim the window will be closed when the job is finished.
- `[cmd]` is the optional command to run. if not specified, the current `shell` option value will be used.

Mappings are provided to smooth the operation of toggling floating terminals and are the **SUGGESTED** way to use instead of the command. Using these mappings are just like run `:Multiterm` without any additional argument.

```lua
-- Map <F12> to toggle the selected terminal window
vim.keymap.set({ "n", "v", "i", "t" }, "<F12>", "<Plug>(Multiterm)"),

-- Map <leader><F12> to open the pop-up list of the active terminal windows
vim.keymap.set("n", "<leader><F12>", "<Plug>(MultitermList)"),
```

Now you could press `<F12>` to toggle the tag `1` floating terminal instance or close the current active floating terminal window that your cursor is in. And press `3<F12>` to activate the tag `3` instance, etc.

The `<Plug>(MultitermList)` keymap provides a way to see all opened multiterm windows conveniently. It opens a popup window with a list of all the active multiterm windows where you can select and open the one you need.

**NOTE** in terminal mode it is impossible to press a number as the tag, but you can still use `<F12>` to close the current terminal window which your cursor is in without specifying its tag.

## Configuration

```lua
-- Default options, do not put this in your configuration file

require("multiterm").setup({
    height = 0.8,
    width = 0.8,
    border = 'rounded',
    term_hl = 'Normal',
    border_hl = 'FloatBorder',
    show_term_tag = true,
    show_backdrop = true,
    backdrop_bg = 'Black',
    backdrop_transparency = 60,
    fullscreen = false,
)}
```

Refer to the doc file for a more detailed explanation.

## Thanks

This plugin is based on `chengzeyi/multiterm.vim`.
