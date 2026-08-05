# competitest.nvim (Custom Enhanced Fork)

An ultra-optimized, feature-enhanced fork of [competitest.nvim](https://github.com/xeluxee/competitest.nvim) tailored for high-speed Competitive Programming in Neovim and LazyVim.

---

## 🚀 Key Enhancements & Custom Features

### 1. Optimized 4-Level Split UI Layout
Reorganized the runner split layout for maximum readability during contest problem solving:

```
+-------------------------------------------------------------+
| 1. Test Case Input (si)   [Dynamic Height: 2 to 20 lines]   |
+-----------------------------------+-------------------------+
| 2. Standard Output (so)           | Expected Output (eo)    |
|    [Header: " OUTPUT "]           | [Header: " EXPECTED "]  |
|                                   | [Auto-width: 8ch empty] |
+-----------------------------------+-------------------------+
| 3. ERRORS Pane (se)               [Header: " ERRORS "]     |
|    [Unhides on error, hidden when clean / floating UI off]  |
+-------------------------------------------------------------+
| 4. Compile Info & Status List (tc) [Dynamic Height = lines] |
+-------------------------------------------------------------+
```

- **Top Pane**: Test Case Input (`si`) dynamically resizes its height between **2 and 20 lines** based on input data size.
- **Middle Panes**: Standard Output (`so`) and Expected Output (`eo`) sit side-by-side with styled header titles (` OUTPUT ` and ` EXPECTED `). When expected output is empty, `eo` automatically shrinks to **8 characters wide**, maximizing space for program output.
- **Errors Pane**: Dedicated **ERRORS** pane (`se`) sits directly above the status list. It automatically unhides when compilation or runtime errors exist, and remains hidden during clean runs.
- **Bottom Pane**: Testcases status list & compile info (`tc`) dynamically resizes its window height to fit the exact line count, avoiding wasted vertical space.

### 2. Sticky Buffer Focus
- Running testcases via `<leader>tr` (`CompetiTest run`) preserves cursor focus inside your active C++ source file (`A.cpp`). You can continue typing and editing without focus getting stolen.

### 3. Precompiled Headers (PCH) & Mold Linker Support
- Fully compatible with C++20 precompiled headers (`bits/stdc++.h.gch` and PBDS `ext/pb_ds/*.gch`) via `-I.` include path resolution.
- Configured to use **`mold`** (the world's fastest C++ linker) and `-O0 -pipe` flags for sub-second compile and test cycles.

### 4. Automatic Binary Cleanup
- Generated executable object files (`./A`, `./A.o`, `./A.out`, `./A.exe`) are cleaned up automatically upon test completion or process cancellation.

### 5. Safe Window Management
- Handled Neovim window closing events to prevent `Vim:E444: Cannot close last window` errors when hiding or closing the runner UI.

---

## 🛠 Installation (LazyVim)

In your Neovim plugin configuration (e.g. `lua/plugins/competitest.lua`):

```lua
return {
  {
    "shubhamvermaa/competitest.nvim",
    dependencies = { "muniftanjim/nui.nvim" },
    cmd = { "CompetiTest" },
    keys = {
      { "<leader>tr", "<cmd>CompetiTest run<cr>", desc = "Run Test Cases" },
      { "<leader>tc", "<cmd>CompetiTest receive contest<cr>", desc = "Receive Contest Testcases" },
      { "<leader>tp", "<cmd>CompetiTest receive problem<cr>", desc = "Receive Problem Testcases" },
      { "<leader>ta", "<cmd>CompetiTest add_testcase<cr>", desc = "Add Test Case" },
      { "<leader>te", "<cmd>CompetiTest edit_testcase<cr>", desc = "Edit Test Case" },
      { "<leader>td", "<cmd>CompetiTest delete_testcase<cr>", desc = "Delete Test Case" },
      { "<leader>tu", "<cmd>CompetiTest show_ui<cr>", desc = "Show Test UI" },
    },
    opts = {
      save_current_file = true,
      runner_ui = {
        interface = "split",
        viewer = {
          open_when_compilation_fails = false,
        },
      },
      split_ui = {
        position = "right",
        relative_to_editor = true,
        total_width = 0.35,
        vertical_layout = {
          { 1, "si" },
          { 2, {
            { 1, "so" },
            { 1, "eo" },
          } },
          { 1, "se" },
          { 1, "tc" },
        },
      },
      compile_command = {
        cpp = { exec = "g++", args = { "-std=c++20", "-O0", "-pipe", "-I.", "-B/home/shubham/.local/bin", "$(FNAME)", "-o", "$(FNOEXT)" } },
      },
      run_command = {
        cpp = { exec = "./$(FNOEXT)" },
      },
    },
  },
}
```

---

## 📄 Original Documentation

The original plugin documentation by [xeluxee](https://github.com/xeluxee) is preserved in [`original_README.md`](original_README.md).
