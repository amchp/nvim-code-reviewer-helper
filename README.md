# nvim-code-reviewer-helper

Neovim plugin for asking Codex to explain selected code, answer questions about the current file, and run repository review sessions using local context.

## Features

- Explains a visual selection with surrounding code, diagnostics, symbol context, and nearby docs such as `README.md` or `AGENTS.md`.
- Supports file-level questions from normal mode when you want repository context for the current buffer.
- Runs `codex exec --ephemeral` locally and writes the final answer into a reusable markdown split inside Neovim.
- Saves explain responses and Review Sessions so they can be reopened later.
- Starts explicit Codebase Review and Git Changes Review sessions.
- Integrates BTCA-style dependency repository context through a local sandbox, with optional auto-sync.
- Uses web search with Codex by default, while still preferring local repository evidence and file citations.

## Requirements

- Neovim `0.11+`
- `codex` installed and authenticated
- `git`

Before using the plugin:

```bash
codex login
codex --help
git --version
```

## Installation

### `lazy.nvim`

```lua
{
  "amchp/nvim-code-reviewer-helper",
  dependencies = {
    -- Optional, used for changed-file guide sessions
    "sindrets/diffview.nvim",
  },
  config = function()
    require("code_reviewer_helper").setup()

    vim.keymap.set("v", "<leader>ce", function()
      require("code_reviewer_helper").explain_visual()
    end, { desc = "Explain selected code" })

    vim.keymap.set("n", "<leader>ce", "<cmd>CRHExplain<cr>", {
      desc = "Ask about current file",
    })

    vim.keymap.set("n", "<leader>cf", "<cmd>CRHAskFile<cr>", {
      desc = "Ask about current file",
    })

    vim.keymap.set("n", "<leader>cr", "<cmd>CRHReviewCodebase<cr>", {
      desc = "Codebase Review",
    })

    vim.keymap.set("n", "<leader>cR", "<cmd>CRHReviewGitChanges<cr>", {
      desc = "Git Changes Review",
    })
  end,
}
```

### Native packpath

```bash
mkdir -p ~/.local/share/nvim/site/pack/local/start
git clone https://github.com/amchp/nvim-code-reviewer-helper.git \
  ~/.local/share/nvim/site/pack/local/start/nvim-code-reviewer-helper
```

Then in your Neovim config:

```lua
require("code_reviewer_helper").setup()
```

## Basic Usage

- `:CRHExplain`
  In visual mode, prompts for an optional question and explains the selection.
  In normal mode, remains backward-compatible and asks for a required repo-level question about the current file.
- `:CRHAskFile`
  Always asks a required question about the current file and captures the whole file without a visual selection.
- `:CRHHistory`
  Opens saved explain responses.
- `:CRHOpenLast`
  Reopens the most recent explain response.
- `:CRHReviewCodebase`
  Starts a Codebase Review. It always reviews repository structure, regardless of dirty git status.
- `:CRHReviewGitChanges`
  Starts a Git Changes Review. It prompts for a positive integer `N`, shows the previous 5 commits, and reviews the aggregate diff from `HEAD~N` to the current working tree.
- `:CRHGuideHistory`
  Opens saved Review Sessions.
- `:CRHGuideOpenLast`
  Reopens the most recent Review Session.
- `:CRHGuidePlan`
  Opens the markdown Review Overview for the active Review Session.
- `:CRHGuideClose`
  Closes the Review Session and saves the current resume position.
- `:CRHGuideHistoryClear`
  Clears saved Review Session history for the current workspace.
- `:CRHBtcaAddRepo [url]`
  Adds a repository URL to the BTCA context list for the current workspace.
- `:CRHHealth`
  Runs environment and integration checks.
- `:CRHNext`, `:CRHPrev`, `:CRHCancel`
  Navigate or cancel explain jobs.

## Minimal Setup

```lua
require("code_reviewer_helper").setup({
  codex = {
    bin = "codex",
    model = "gpt-5.4-mini",
    sandbox = "workspace-write",
    ephemeral = true,
    use_web_search = true,
  },
  btca = {
    enabled = true,
    auto_sync = false,
    max_repositories = 5,
  },
})
```

The previous CRHGuide command has been removed from the public command surface. Use `:CRHReviewCodebase` or `:CRHReviewGitChanges`.

## Review Sessions

A Review Session starts with a virtual `Review Overview` item. This is a scratch buffer, not a real repository file.

Codebase Review builds repository inventory, includes docs such as `README.md` and `AGENTS.md`, and asks Codex for a first-pass file order. The native UI uses exactly two windows: a 30% switcher/list pane and a 70% file viewer. It does not open git changes or diff panes.

Git Changes Review prompts for `N` and reviews one combined diff from `HEAD~N` to the current working tree. The review includes committed changes in `HEAD~N..HEAD`, uncommitted tracked changes, and untracked files when `guide.include_untracked = true`. Overlapping changes are shown once in their final resulting state. The native UI uses a 30% switcher/list pane and splits the remaining 70% into before/after diff panes. If `diffview.nvim` is installed, Git Changes Review can use Diffview; otherwise it uses the native fallback.

Suggested keymaps:

```lua
vim.keymap.set("v", "<leader>ce", "<cmd>CRHExplain<cr>", { desc = "Explain selection" })
vim.keymap.set("n", "<leader>cf", "<cmd>CRHAskFile<cr>", { desc = "Ask current file" })
vim.keymap.set("n", "<leader>cr", "<cmd>CRHReviewCodebase<cr>", { desc = "Codebase Review" })
vim.keymap.set("n", "<leader>cR", "<cmd>CRHReviewGitChanges<cr>", { desc = "Git Changes Review" })
vim.keymap.set("n", "<leader>cl", "<cmd>CRHGuideOpenLast<cr>", { desc = "Open last Review Session" })
```

## BTCA Repository Context

When BTCA is enabled, the plugin can include extra repository context from a local sandbox directory. It resolves likely dependency repositories from files such as:

- `package.json`
- `go.mod`
- `Cargo.toml`
- `pyproject.toml`
- `requirements.txt`

You can also add repositories manually:

```vim
:CRHBtcaAddRepo https://github.com/owner/repo
```

Useful BTCA options:

```lua
require("code_reviewer_helper").setup({
  btca = {
    enabled = true,
    auto_sync = true,
    max_repositories = 5,
    sandbox_dir = vim.fn.expand("~/.btca/agent/sandbox"),
  },
})
```

## Health Check

`:CRHHealth` verifies:

- `codex` is executable
- `git` is executable
- the BTCA skill is installed or a fallback prompt is available
- the BTCA sandbox directory is writable
- the current workspace root can be resolved

It does not perform a live authentication probe; run `:CRHExplain` to confirm your active Codex session works end-to-end.

## Development

Run tests with:

```bash
make test
```

## License

MIT. See [LICENSE](LICENSE).
