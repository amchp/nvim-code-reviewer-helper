# nvim-code-reviewer-helper

Neovim plugin for asking Codex to explain selected code, answer questions about the current file, and generate guided review plans using local repository context.

## Features

- Explains a visual selection with surrounding code, diagnostics, symbol context, and nearby docs such as `README.md` or `AGENTS.md`.
- Supports file-level questions from normal mode when you want repository context for the current buffer.
- Runs `codex exec` locally and writes the final answer into a reusable markdown split inside Neovim.
- Saves explain responses and guided review sessions so they can be reopened later.
- Builds guided review plans with `:CRHGuide` for either current git changes or a first-pass repo walkthrough.
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

    vim.keymap.set("n", "<leader>cg", "<cmd>CRHGuide<cr>", {
      desc = "Start guided review",
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
  In normal mode, asks for a required repo-level question about the current file.
- `:CRHHistory`
  Opens saved explain responses.
- `:CRHOpenLast`
  Reopens the most recent explain response.
- `:CRHGuide`
  Generates a guided review plan for current changes or the whole repo.
- `:CRHGuideHistory`
  Opens saved guided review sessions.
- `:CRHGuideOpenLast`
  Reopens the most recent guided review.
- `:CRHGuidePlan`
  Opens the markdown plan for the active guided review.
- `:CRHGuideClose`
  Closes the guide and saves the current resume position.
- `:CRHGuideHistoryClear`
  Clears saved guided review history for the current workspace.
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
    use_web_search = true,
  },
  btca = {
    enabled = true,
    auto_sync = false,
    max_repositories = 5,
  },
})
```

## Guided Review

`:CRHGuide` inspects the current workspace and chooses a mode automatically:

- If the git worktree has tracked or untracked changes, it generates a review plan for those changes.
- If the worktree is clean, it generates a first-pass walkthrough for the repository.

Guide sessions are persisted under Neovim state, and the plugin can reopen the last session at the saved file position. If `diffview.nvim` is installed, changed-file guide sessions use Diffview; otherwise the plugin falls back to its native tab UI.

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
