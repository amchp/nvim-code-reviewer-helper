# code-reviewer-helper

Neovim plugin for visually selecting code and asking Codex for short explanations with citations, using local repo context, BTCA-style instructions, and optional web documentation.

## What It Does

- Captures a visual selection plus surrounding code.
- Adds workspace docs such as `AGENTS.md` and `README.md`.
- Discovers dependency repositories from the active workspace and exposes synced clones from `~/.btca/agent/sandbox`.
- Auto-installs the BTCA skill into Codex's global skills directory when it is missing.
- Runs `codex exec` in explain-only mode with `gpt-5.4-mini` by default.
- Opens the response in a reusable right-side markdown split.
- Wraps long lines in that response split so the explanation stays readable.
- Prefers local file citations and only leans on web docs when they materially help.
- Saves responses so you can reopen them later with `:CRHHistory`.
- Adds `:CRHGuide` to build a guided review order for either current git changes or the whole repository.
- Opens a guided review tab with an ordered file list and either a single-file pane or a diff-style view.

## Prerequisites

```bash
codex login
codex --help
git --version
```

Neovim `0.11+` is recommended.

## Install With `lazy.nvim`

```lua
{
  dir = "/home/automac/Documents/Projects/code-reviewer-helper",
  name = "code-reviewer-helper",
  dependencies = {},
  config = function()
    require("code_reviewer_helper").setup({
      btca = {
        enabled = true,
      },
    })

    vim.keymap.set("v", "<leader>ce", function()
      require("code_reviewer_helper").explain_visual()
    end, { desc = "Explain selected code" })

    vim.keymap.set("n", "<leader>e", "<cmd>CRHExplain<cr>", {
      desc = "Ask repo question about current file",
    })
  end,
}
```

## Install With Native Packpath

```bash
mkdir -p ~/.local/share/nvim/site/pack/local/start
ln -s /home/automac/Documents/Projects/code-reviewer-helper \
  ~/.local/share/nvim/site/pack/local/start/code-reviewer-helper
```

Then add this to your Neovim config:

```lua
require("code_reviewer_helper").setup({
  btca = {
    enabled = true,
  },
})

vim.keymap.set("v", "<leader>ce", function()
  require("code_reviewer_helper").explain_visual()
end, { desc = "Explain selected code" })

vim.keymap.set("n", "<leader>e", "<cmd>CRHExplain<cr>", {
  desc = "Ask repo question about current file",
})
```

## Minimal Config

```lua
require("code_reviewer_helper").setup({
  codex = {
    bin = "codex",
    model = "gpt-5.4-mini",
  },
  btca = {
    enabled = true,
  },
})
```

## Recommended Visual Keymap

```lua
vim.keymap.set("v", "<leader>ce", function()
  require("code_reviewer_helper").explain_visual()
end, { desc = "Explain selected code" })

vim.keymap.set("n", "<leader>e", "<cmd>CRHExplain<cr>", {
  desc = "Ask repo question about current file",
})
```

## Local Install For Testing

Use the `lazy.nvim` or native packpath setup above with the exact local path:

`/home/automac/Documents/Projects/code-reviewer-helper`

For this local-path setup, you do not reinstall after code changes. Neovim is reading the plugin directly from this repo.

- If you edit the plugin while Neovim is closed: just reopen Neovim.
- If Neovim is already open: restart it to pick up Lua/module changes reliably.
- If you use the native packpath symlink, the same rule applies: update the repo, then restart Neovim.

## How To Test The Plugin Locally

1. Open Neovim inside any git repo.
2. Run `:CRHHealth`.
3. Open a source file.
4. Enter visual mode and select a few lines.
5. Run `:CRHExplain`.
6. Press Enter for the internal fallback question, or type your own question.
7. Confirm the markdown explanation appears in the right split with short output and citations.
8. Run `:CRHHistory` and reopen the saved response.

`:CRHExplain` opens with an empty input box. If you submit it blank, the plugin falls back to its internal default question. If you type a question, that exact question is used.

When `:CRHExplain` runs in normal mode, it asks for a repo-level question about the current file. That prompt requires a non-empty question and sends the whole current file as context.

## Commands

- `:CRHExplain`
- `:CRHHistory`
- `:CRHOpenLast`
- `:CRHNext`
- `:CRHPrev`
- `:CRHCancel`
- `:CRHBtcaSync`
- `:CRHHealth`
- `:CRHGuide`
- `:CRHGuideHistory`
- `:CRHGuideOpenLast`
- `:CRHGuideHistoryClear`
- `:CRHGuideClose`
- `:CRHGuidePlan`

## Guided Review

Run `:CRHGuide` from inside a repository to ask Codex for the best order to understand the current changes or, if the repo is clean, the best first-pass order for understanding the codebase.

- If `git status --porcelain=v1 --untracked-files=all` is non-empty, the guide starts in `changes` mode.
- Otherwise it starts in `repo` mode.
- The session stores a markdown plan under Neovim state and reopens it with `:CRHGuidePlan`.
- Saved guide history records the HEAD commit name for git-backed walkthroughs.
- If `diffview.nvim` is installed, changed-file sessions use Diffview's custom diff view API.
- Without `diffview.nvim`, the plugin falls back to a native tab with a left file list and right content panes.
- Closing a guide saves the current file position, and `:CRHGuideOpenLast` resumes from that file.

Within a guide session:

- `<Tab>` moves to the next file.
- `<S-Tab>` moves to the previous file.
- `gp` opens the guide plan.
- `q` closes the guide tab.

Useful guide commands:

- `:CRHGuideOpenLast` reopens the last saved guide at its last saved file.
- `:CRHGuideClose` closes the guide and saves the current file as the resume point.
- `:CRHGuideHistoryClear` clears saved guide history for the current workspace.

## BTCA Dependency Repositories

`BTCA` no longer seeds the sandbox with fixed example repositories.

Instead, the plugin resolves repositories from the current workspace, keeps a small high-signal subset, and uses the sandbox for synced dependency clones that Codex can inspect alongside your project.

Current discovery is intentionally conservative:

- `package.json` direct git or GitHub-style dependencies
- `go.mod` dependencies hosted on `github.com`, `gitlab.com`, or `bitbucket.org`
- `Cargo.toml` dependencies with explicit `git = "..."`
- `pyproject.toml` and `requirements.txt` git-based dependencies
- optional manual extras from `btca.repositories`

The plugin does not sync every discovered repo by default. It ranks candidates and keeps the most important few, preferring manual entries and runtime dependencies over lower-signal sources like dev-only dependencies.

You can tune the shortlist size with:

```lua
require("code_reviewer_helper").setup({
  btca = {
    max_repositories = 5,
  },
})
```

If you want the sandbox kept up to date automatically before each explain request, enable:

```lua
require("code_reviewer_helper").setup({
  btca = {
    auto_sync = true,
  },
})
```

Otherwise run `:CRHBtcaSync` from inside the repository you are reviewing.

## What `:CRHHealth` Checks

- `codex` binary is executable
- `git` is executable
- BTCA skill file exists, or can be installed from embedded BTCA instructions
- BTCA sandbox directory exists or can be created
- current buffer resolves to a workspace root
- whether visual mode is currently active
- how many BTCA repos are already visible in the sandbox
- how many prioritized dependency repositories the current workspace resolves

It does not send a live Codex request, so authentication is only inferred from local setup. The real end-to-end auth check is running `:CRHExplain`.

## Troubleshooting

### `codex` not found

Set `codex.bin` in `setup()` to the full executable path.

### Codex auth fails during `:CRHExplain`

Run `codex login` in a terminal, then retry.

### Explanations are still too long

The plugin now biases the prompt toward short answers with a small `Sources` section. If you want even shorter responses, ask a narrower question in the prompt box.

### No visual selection found

This only applies to the visual-selection flow. Start in visual mode, select the lines, and run `:CRHExplain` from that selection or from a visual keymap. In normal mode, `:CRHExplain` asks a repo question about the current file instead.

### BTCA skill file missing

The plugin tries to install the BTCA skill file automatically from its embedded BTCA instructions. If you want strict behavior, set:

```lua
require("code_reviewer_helper").setup({
  btca = {
    fallback_prompt = false,
  },
})
```

## Development

Run the headless tests with:

```bash
make test
```
