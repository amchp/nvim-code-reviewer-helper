local t = require("code_review_helper_test.support")

local M = {}

local function helper_with_config(extra)
  local helper = t.load_helper()
  local root = t.tmp_dir("workspace")
  vim.system({ "git", "-C", root, "init" }, { text = true }):wait()
  local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_success.sh"

  helper.setup(vim.tbl_deep_extend("force", {
    codex = {
      bin = fake_bin,
      use_web_search = true,
    },
    btca = {
      sandbox_dir = t.tmp_dir("btca"),
      skill_path = t.tmp_dir("skill") .. "/SKILL.md",
    },
    history = {
      persist = false,
    },
  }, extra or {}))

  return helper, root
end

local function git(cwd, args)
  local command = { "git", "-C", cwd }
  vim.list_extend(command, args)
  return vim.system(command, { text = true }):wait()
end

local function commit_all(root, message)
  git(root, { "add", "." })
  git(root, { "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", message })
end

local function seed_git_repo(root, files)
  git(root, { "init" })
  for path, content in pairs(files or {}) do
    t.write(root .. "/" .. path, content)
  end
  commit_all(root, "seed")
end

local function create_bare_repo(name, files)
  local source = t.tmp_dir(name .. "_source")
  seed_git_repo(source, files or {
    ["README.md"] = "# " .. name .. "\n",
  })

  local bare = t.tmp_dir(name .. "_bare_parent") .. "/" .. name .. ".git"
  git(source, { "clone", "--bare", source, bare })
  return bare
end

local function helper_with_guide_config(fake_bin, extra)
  local helper = t.load_helper()
  local root = t.tmp_dir("guide_workspace")
  git(root, { "init" })
  helper.setup(vim.tbl_deep_extend("force", {
    codex = {
      bin = fake_bin,
      use_web_search = false,
    },
    btca = {
      sandbox_dir = t.tmp_dir("guide_btca"),
      skill_path = t.tmp_dir("guide_skill") .. "/SKILL.md",
    },
    history = {
      persist = false,
    },
    guide = {
      persist = false,
      use_diffview_if_available = true,
    },
  }, extra or {}))

  return helper, root
end

local function seed_repo_workspace(root)
  t.write(root .. "/README.md", "# Demo\n")
  t.write(root .. "/plugin/code_reviewer_helper.lua", "return {}\n")
  t.write(root .. "/lua/code_reviewer_helper/init.lua", "return {}\n")
end

local function seed_changes_workspace(root)
  t.write(root .. "/modified.lua", "local value = 1\nreturn value\n")
  t.write(root .. "/deleted.lua", "return 'deleted'\n")
  t.write(root .. "/renamed_old.lua", "return 'old'\n")
  commit_all(root, "seed")

  t.write(root .. "/modified.lua", "local value = 2\nreturn value\n")
  git(root, { "mv", "renamed_old.lua", "renamed_new.lua" })
  t.write(root .. "/added.lua", "return 'new'\n")
  vim.uv.fs_unlink(root .. "/deleted.lua")
end

local function wait_for_guide_session(helper)
  return vim.wait(2000, function()
    return helper.__state().guide_session ~= nil
  end)
end

local function current_tab_content_buffers()
  local bufs = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    table.insert(bufs, vim.api.nvim_win_get_buf(win))
  end
  return bufs
end

local function find_buffer_by_name(pattern)
  for _, buf in ipairs(current_tab_content_buffers()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match(pattern) then
      return buf
    end
  end
  return nil
end

local function find_win_for_buf(tabpage, bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

local function make_retry_fake_bin()
  local dir = t.tmp_dir("guide_retry_fake")
  local script = dir .. "/codex_guide_retry.sh"
  local counter = dir .. "/counter"
  t.write(script, string.format([=[
#!/usr/bin/env bash
set -euo pipefail

output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

count=0
if [[ -f %q ]]; then
  count="$(cat %q)"
fi
count=$((count + 1))
printf '%%s' "$count" > %q

cat >/dev/null

if [[ "$count" == "1" ]]; then
  cat >"$output" <<'EOF'
```json
{"mode":"repo","summary":"wrong repo","items":[{"path":".github/workflows/test-pr.yml","reason":"hallucinated path","status":"repo","old_path":null}]}
```
# Review Order

1. .github/workflows/test-pr.yml
EOF
  exit 0
fi

cat >"$output" <<'EOF'
```json
{"mode":"repo","summary":"Review the repo entrypoints first.","items":[{"path":"README.md","reason":"Start with the top-level documentation.","status":"repo","old_path":null},{"path":"plugin/code_reviewer_helper.lua","reason":"Then inspect the Neovim plugin entrypoint.","status":"repo","old_path":null}]}
```
# Review Order

Overall summary: review README.md first, then the plugin entrypoint.

1. README.md - Start with the top-level documentation.
2. plugin/code_reviewer_helper.lua - Then inspect the Neovim plugin entrypoint.
EOF
]=], counter, counter, counter))
  vim.system({ "chmod", "+x", script }, { text = true }):wait()
  return script, counter
end

local function make_utf8_validating_fake_bin()
  local dir = t.tmp_dir("guide_utf8_fake")
  local script = dir .. "/codex_guide_utf8.sh"
  t.write(script, [=[
#!/usr/bin/env bash
set -euo pipefail

output=""
stdin_file="$(mktemp)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

cat >"$stdin_file"

python3 - "$stdin_file" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.read_bytes().decode("utf-8")
PY

cat >"$output" <<'EOF'
```json
{"mode":"repo","summary":"Start at the docs first.","items":[{"path":"README.md","reason":"Start with the top-level docs.","status":"repo","old_path":null}]}
```
# Review Order

Start at the docs first.

1. `README.md` - Start with the top-level docs.
EOF
]=])
  vim.system({ "chmod", "+x", script }, { text = true }):wait()
  return script
end

function M.tests()
  return {
    {
      name = "config normalizes defaults",
      run = function()
        local config = require("code_reviewer_helper.config").normalize({})
        t.eq("codex", config.codex.bin)
        t.eq("gpt-5.4-mini", config.codex.model)
        t.eq(true, config.codex.ephemeral)
        t.eq(true, config.btca.enabled)
        t.eq(0, #config.btca.repositories)
        t.eq(5, config.btca.max_repositories)
        t.match("Explain this code", config.prompt.default_question)
      end,
    },
    {
      name = "btca resolves repositories from dependency manifests",
      run = function()
        local workspace = t.tmp_dir("btca_workspace")
        t.write(workspace .. "/package.json", vim.json.encode({
          dependencies = {
            example = "https://github.com/acme/example.git#main",
            widgets = "acme/widgets",
          },
        }))
        t.write(workspace .. "/go.mod", table.concat({
          "module demo",
          "",
          "require github.com/cli/go-gh v1.4.0",
          "",
        }, "\n"))

        local repos = require("code_reviewer_helper.btca").resolve_repositories({
          sandbox_dir = t.tmp_dir("btca_resolve"),
          repositories = {},
        }, workspace)

        local names = {}
        for _, repo in ipairs(repos) do
          table.insert(names, repo.name)
        end

        t.eq(3, #repos)
        t.match("github.com/acme/example", table.concat(names, "\n"))
        t.match("github.com/acme/widgets", table.concat(names, "\n"))
        t.match("github.com/cli/go%-gh", table.concat(names, "\n"))
      end,
    },
    {
      name = "btca prioritizes important repositories over low-signal ones",
      run = function()
        local workspace = t.tmp_dir("btca_priority_workspace")
        t.write(workspace .. "/package.json", vim.json.encode({
          dependencies = {
            runtime = "acme/runtime-core",
          },
          devDependencies = {
            tooling = "acme/dev-only",
          },
        }))

        local repos = require("code_reviewer_helper.btca").resolve_repositories({
          sandbox_dir = t.tmp_dir("btca_priority"),
          repositories = { "https://github.com/acme/manual-important.git" },
          max_repositories = 2,
        }, workspace)

        local names = {}
        for _, repo in ipairs(repos) do
          table.insert(names, repo.name)
        end

        t.eq(2, #repos)
        t.match("github.com/acme/manual%-important", names[1])
        t.match("github.com/acme/runtime%-core", table.concat(names, "\n"))
        if table.concat(names, "\n"):match("github.com/acme/dev%-only") then
          error("low-signal dev dependency should be excluded when max_repositories is reached")
        end
      end,
    },
    {
      name = "ensure_utf8 replaces invalid byte sequences",
      run = function()
        local util = require("code_reviewer_helper.util")

        t.eq("a?b", util.ensure_utf8("a" .. string.char(255) .. "b"))
        t.eq("???", util.ensure_utf8(string.char(237, 160, 128)))
      end,
    },
    {
      name = "btca sync clones discovered dependency repositories",
      run = function()
        local bare = create_bare_repo("dep_repo", {
          ["lua/dep.lua"] = "return { value = 42 }\n",
        })
        local workspace = t.tmp_dir("btca_sync_workspace")
        t.write(workspace .. "/package.json", vim.json.encode({
          dependencies = {
            dep = "git+file://" .. bare,
          },
        }))

        local config = {
          sandbox_dir = t.tmp_dir("btca_sync"),
          repositories = {},
        }
        local btca = require("code_reviewer_helper.btca")
        local messages = btca.sync(config, workspace)
        local repos = btca.resolve_repositories(config, workspace)

        t.match("cloned dep_repo", table.concat(messages, "\n"))
        t.eq(1, #repos)
        t.eq(true, repos[1].available)
      end,
    },
    {
      name = "btca add manual repository persists and deduplicates per workspace",
      run = function()
        local bare = create_bare_repo("manual_dep", {
          ["README.md"] = "# Manual dep\n",
        })
        local workspace = t.tmp_dir("btca_add_workspace")
        local config = {
          sandbox_dir = t.tmp_dir("btca_add_sandbox"),
          repositories = {},
          max_repositories = 5,
        }
        local btca = require("code_reviewer_helper.btca")

        local ok, message = btca.add_manual_repository(config, workspace, "git+file://" .. bare)
        t.eq(true, ok)
        t.match("added manual_dep", message)
        t.match("cloned manual_dep", message)

        ok, message = btca.add_manual_repository(config, workspace, "file://" .. bare)
        t.eq(true, ok)
        t.match("already added manual_dep", message)

        local saved = btca.manual_repositories(workspace)
        t.eq(1, #saved)
        t.eq("file://" .. bare, saved[1])

        local repos = btca.resolve_repositories(config, workspace)
        t.eq(1, #repos)
        t.eq("manual_dep", repos[1].name)
        t.eq(true, repos[1].available)
        t.match("btca.added", table.concat(repos[1].sources, "\n"))
      end,
    },
    {
      name = "prompt includes BTCA and docs",
      run = function()
        local prompt = require("code_reviewer_helper.prompt").build("why", {
          path = "/tmp/file.lua",
          filetype = "lua",
          range = {
            start_row = 1,
            start_col = 1,
            end_row = 2,
            end_col = 4,
          },
          selected_lines = { "local x = 1" },
          surrounding_lines = {
            before = { "local y = 2" },
            after = { "return x" },
          },
          diagnostics = {
            {
              severity = "WARN",
              row = 1,
              col = 1,
              message = "demo",
            },
          },
          symbol = "function_declaration",
        }, {
          workspace_root = "/tmp",
          docs = {
            {
              relative_path = "README.md",
              content = "hello",
            },
          },
          btca_skill = "btca instructions",
          btca_repos = {
            {
              name = "github.com/acme/example",
              path = "/tmp/99",
              available = true,
              sources = { "package.json" },
            },
          },
        })
        t.match("BTCA Instructions", prompt)
        t.match("BTCA Dependency Repositories", prompt)
        t.match("README%.md", prompt)
        t.match("function_declaration", prompt)
        t.match("Give a short explanation, not a deep review", prompt)
        t.match("Prefer repository evidence first", prompt)
        t.match("End with a Sources section", prompt)
        t.match("Prefer under 120 words before the Sources section", prompt)
      end,
    },
    {
      name = "selection captures marked text",
      run = function()
        local path = t.tmp_dir("selection") .. "/file.lua"
        local buf = t.new_buffer({
          "local function demo()",
          "  return 42",
          "end",
        }, path)
        t.set_visual_marks(buf, 1, 1, 2, 10)
        local selection = require("code_reviewer_helper.selection").capture({
          allow_marks = true,
          require_visual_mode = true,
          max_selection_lines = 10,
          surrounding_lines = 1,
          include_diagnostics = false,
          include_symbol_context = false,
        })
        t.eq(2, #selection.selected_lines)
        t.match("local function", selection.selected_lines[1])
      end,
    },
    {
      name = "selection captures full lines in live linewise visual mode",
      run = function()
        local path = t.tmp_dir("selection_linewise") .. "/file.lua"
        local buf = t.new_buffer({
          "[1, 2, 3]",
          "return value",
        }, path)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.cmd("normal! V")

        local selection = require("code_reviewer_helper.selection").capture({
          allow_marks = true,
          require_visual_mode = true,
          max_selection_lines = 10,
          surrounding_lines = 0,
          include_diagnostics = false,
          include_symbol_context = false,
        })

        vim.cmd("normal! \27")

        t.eq(1, #selection.selected_lines)
        t.eq("[1, 2, 3]", selection.selected_lines[1])
      end,
    },
    {
      name = "command builder enables web search and BTCA add-dir",
      run = function()
        local command = require("code_reviewer_helper.provider.codex_exec").build_command({
          workspace_root = "/tmp/project",
        }, {
          codex = {
            bin = "codex",
            sandbox = "workspace-write",
            ephemeral = true,
            use_web_search = true,
            extra_args = { "--json" },
            model = "gpt-5.4",
          },
          btca = {
            enabled = true,
            sandbox_dir = "/tmp/btca",
          },
        }, "/tmp/out")
        t.eq("codex", command[1])
        t.eq("--search", command[2])
        t.eq("exec", command[3])
        t.ok(vim.tbl_contains(command, "--ephemeral"))
        t.ok(vim.tbl_contains(command, "/tmp/btca"))
        t.ok(vim.tbl_contains(command, "gpt-5.4"))
      end,
    },
    {
      name = "health reports missing visual mode as warning",
      run = function()
        local helper = t.load_helper()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_success.sh"
        helper.setup({
          codex = { bin = fake_bin },
          btca = {
            sandbox_dir = t.tmp_dir("health_btca"),
            skill_path = t.tmp_dir("health_skill") .. "/missing.md",
          },
          history = { persist = false },
        })
        local ok, lines = pcall(helper.health)
        t.ok(ok)
        t.match("visual mode is not active", table.concat(lines, "\n"))
      end,
    },
    {
      name = "setup installs the BTCA skill file when missing",
      run = function()
        local helper = t.load_helper()
        local skill_path = t.tmp_dir("btca_install") .. "/SKILL.md"

        helper.setup({
          btca = {
            sandbox_dir = t.tmp_dir("btca_install_sandbox"),
            skill_path = skill_path,
          },
          history = { persist = false },
        })

        t.eq(true, require("code_reviewer_helper.util").file_exists(skill_path))
        local content = require("code_reviewer_helper.util").read_file(skill_path) or ""
        t.match("^%-%-%-", content)
        t.match("name: btca%-local", content)
        t.match("BTCA Local instructions", content)
      end,
    },
    {
      name = "setup repairs legacy BTCA skill files without frontmatter",
      run = function()
        local helper = t.load_helper()
        local skill_path = t.tmp_dir("btca_legacy") .. "/SKILL.md"
        t.write(skill_path, "BTCA Local instructions:\n- legacy\n")

        helper.setup({
          btca = {
            sandbox_dir = t.tmp_dir("btca_legacy_sandbox"),
            skill_path = skill_path,
          },
          history = { persist = false },
        })

        local content = require("code_reviewer_helper.util").read_file(skill_path) or ""
        t.match("^%-%-%-", content)
        t.match("name: btca%-local", content)
        t.match("BTCA Local instructions", content)
      end,
    },
    {
      name = "helper add_btca_repo adds a repository for the current workspace",
      run = function()
        local helper, root = helper_with_config()
        local bare = create_bare_repo("helper_dep", {
          ["lua/helper_dep.lua"] = "return true\n",
        })
        local file = root .. "/README.md"
        t.write(file, "# Workspace\n")
        local buf = t.new_buffer({ "# Workspace" }, file)
        vim.api.nvim_set_current_buf(buf)

        local ok, message = helper.add_btca_repo("file://" .. bare)
        t.eq(true, ok)
        t.match("added helper_dep", message)

        local repos = require("code_reviewer_helper.btca").resolve_repositories(
          helper.__state().config.btca,
          root
        )
        t.eq(1, #repos)
        t.eq("helper_dep", repos[1].name)
        t.eq(true, repos[1].available)
      end,
    },
    {
      name = "successful explain request writes history and response buffer",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/demo.lua"
        t.write(file, "local function demo()\n  return 42\nend\n")
        local buf = t.new_buffer({
          "local function demo()",
          "  return 42",
          "end",
        }, file)
        t.set_visual_marks(buf, 1, 1, 2, 11)

        helper.explain_visual({
          additional_prompt = "Explain this",
        })
        vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end)

        local entries = require("code_reviewer_helper.history").list()
        t.eq(1, #entries)
        t.match("Stub explanation", entries[1].response_markdown)
        local split_winid = helper.__state().split_winid
        t.eq(true, vim.wo[split_winid].wrap)
        t.eq(true, vim.wo[split_winid].linebreak)
        t.eq(true, vim.wo[split_winid].breakindent)
        t.eq({ 1, 0 }, vim.api.nvim_win_get_cursor(split_winid))
        local split_bufnr = helper.__state().split_bufnr
        local split_text = table.concat(
          vim.api.nvim_buf_get_lines(split_bufnr, 0, -1, false),
          "\n"
        )
        if split_text:match("## stderr") then
          error("successful responses should not render stderr")
        end
        if split_text:match("## Saved Questions") then
          error("successful responses should not render saved question metadata")
        end
        if split_text:match("# Code Review Helper") then
          error("successful responses should not render the helper header")
        end
        t.match("## Question", split_text)
        t.match("Explain this", split_text)
        t.match("## Code Preview", split_text)
        t.match("local function demo%(", split_text)
      end,
    },
    {
      name = "blank input falls back to default question",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/blank_prompt.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\n")
        local buf = t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
        }, file)
        t.set_visual_marks(buf, 1, 1, 1, 15)

        local captured_opts
        local original_input = vim.ui.input
        vim.ui.input = function(opts, callback)
          captured_opts = opts
          callback("")
        end

        local ok, err = pcall(function()
          helper.explain_visual()
          vim.wait(2000, function()
            local entries = require("code_reviewer_helper.history").list()
            return #entries == 1
          end)
        end)
        vim.ui.input = original_input

        if not ok then
          error(err)
        end

        t.eq(nil, captured_opts.default)
        local entries = require("code_reviewer_helper.history").list()
        t.eq(helper.__state().config.prompt.default_question, entries[1].question)
      end,
    },
    {
      name = "custom input uses the exact user question",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/custom_prompt.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\n")
        local buf = t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
        }, file)
        t.set_visual_marks(buf, 1, 1, 1, 15)

        local original_input = vim.ui.input
        vim.ui.input = function(_, callback)
          callback("What is the main dependency here?")
        end

        local ok, err = pcall(function()
          helper.explain_visual()
          vim.wait(2000, function()
            local entries = require("code_reviewer_helper.history").list()
            return #entries == 1
          end)
        end)
        vim.ui.input = original_input

        if not ok then
          error(err)
        end

        local entries = require("code_reviewer_helper.history").list()
        t.eq("What is the main dependency here?", entries[1].question)
      end,
    },
    {
      name = "normal mode explain rejects blank current-file question",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/repo_question.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\n")
        t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
        }, file)

        local captured_opts
        local notifications = {}
        local original_input = vim.ui.input
        local original_notify = vim.notify
        vim.ui.input = function(opts, callback)
          captured_opts = opts
          callback("")
        end
        vim.notify = function(msg, level, opts)
          table.insert(notifications, {
            msg = msg,
            level = level,
            opts = opts,
          })
        end

        local ok, err = pcall(function()
          helper.explain()
          vim.wait(200, function()
            return #notifications > 0
          end)
        end)
        vim.ui.input = original_input
        vim.notify = original_notify

        if not ok then
          error(err)
        end

        t.eq("Repo question for current file: ", captured_opts.prompt)
        t.eq(1, #notifications)
        t.match("repo question is required", notifications[1].msg)
        local entries = require("code_reviewer_helper.history").list()
        t.eq(0, #entries)
      end,
    },
    {
      name = "normal mode explain sends the whole current file",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/repo_file.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\nreturn alpha + beta\n")
        t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
          "return alpha + beta",
        }, file)

        local original_input = vim.ui.input
        vim.ui.input = function(_, callback)
          callback("How does this file fit into the repo?")
        end

        local ok, err = pcall(function()
          helper.explain()
          vim.wait(2000, function()
            local entries = require("code_reviewer_helper.history").list()
            return #entries == 1
          end)
        end)
        vim.ui.input = original_input

        if not ok then
          error(err)
        end

        local entries = require("code_reviewer_helper.history").list()
        t.eq(1, #entries)
        t.eq("How does this file fit into the repo?", entries[1].question)
        t.eq(file, entries[1].path)
        t.eq(1, entries[1].range.start_row)
        t.eq(3, entries[1].range.end_row)
        t.match("local alpha = 1", entries[1].selection_preview)
        t.match("return alpha %+ beta", entries[1].selection_preview)
      end,
    },
    {
      name = "selection is captured before vim.ui.input runs",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/prompt_capture.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\n")
        local buf = t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
        }, file)
        t.set_visual_marks(buf, 1, 1, 1, 15)

        local original_input = vim.ui.input
        vim.ui.input = function(_, callback)
          vim.api.nvim_buf_del_mark(buf, "<")
          vim.api.nvim_buf_del_mark(buf, ">")
          callback("Explain prompt-captured selection")
        end

        local ok, err = pcall(function()
          helper.explain_visual()
          vim.wait(2000, function()
            return helper.__state().current_response_id ~= nil
          end)
        end)
        vim.ui.input = original_input

        if not ok then
          error(err)
        end

        local entries = require("code_reviewer_helper.history").list()
        t.eq(1, #entries)
        t.match("Stub explanation", entries[1].response_markdown)
      end,
    },
    {
      name = "prompt input exits visual mode before opening input",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/visual_exit.lua"
        t.write(file, "local alpha = 1\nlocal beta = 2\n")
        t.new_buffer({
          "local alpha = 1",
          "local beta = 2",
        }, file)
        vim.cmd("normal! gg0v$")

        local seen_mode
        local original_input = vim.ui.input
        vim.ui.input = function(_, callback)
          seen_mode = vim.fn.mode()
          callback("Explain visual exit")
        end

        local ok, err = pcall(function()
          helper.explain_visual()
          vim.wait(2000, function()
            local entries = require("code_reviewer_helper.history").list()
            return #entries == 1
          end)
        end)
        vim.ui.input = original_input

        if not ok then
          error(err)
        end

        t.eq("n", seen_mode)
      end,
    },
    {
      name = "failed explain request records stderr",
      run = function()
        local helper, root = helper_with_config({
          codex = {
            bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_fail.sh",
          },
        })
        local file = root .. "/demo.lua"
        t.write(file, "local x = 1\n")
        local buf = t.new_buffer({ "local x = 1" }, file)
        t.set_visual_marks(buf, 1, 1, 1, 11)

        helper.explain_visual({
          additional_prompt = "Explain fail",
        })
        vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries > 0
        end)

        local entries = require("code_reviewer_helper.history").list()
        t.eq("failed", entries[1].status)
        t.match("forced failure", entries[1].stderr)
        local split_text = table.concat(
          vim.api.nvim_buf_get_lines(helper.__state().split_bufnr, 0, -1, false),
          "\n"
        )
        t.match("# Code Review Helper", split_text)
        t.match("## Saved Questions", split_text)
        t.match("## Question", split_text)
        t.match("## Code Preview", split_text)
        t.match("## stderr", split_text)
      end,
    },
    {
      name = "new completions do not replace the currently open response",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/queue.lua"
        t.write(file, "local one = 1\nlocal two = 2\n")
        local buf = t.new_buffer({
          "local one = 1",
          "local two = 2",
        }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "First question",
        })
        vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end)

        local first_id = helper.__state().current_response_id

        t.set_visual_marks(buf, 2, 1, 2, 13)
        helper.explain_visual({
          additional_prompt = "Second question",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 2
        end))

        local entries = require("code_reviewer_helper.history").list()
        t.eq(2, #entries)
        t.eq(first_id, helper.__state().current_response_id)
      end,
    },
    {
      name = "completed explanations do not auto-open outside normal mode",
      run = function()
        local helper, root = helper_with_config({
          codex = {
            bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_sleep_short.sh",
          },
        })
        local file = root .. "/slow_queue.lua"
        t.write(file, "local one = 1\n")
        local buf = t.new_buffer({ "local one = 1" }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })

        vim.cmd("normal! v")
        t.eq(true, vim.wait(2000, function()
          return not require("code_reviewer_helper.util").mode_is_normal()
        end))

        t.eq(true, vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 1
        end))
        t.eq(nil, helper.__state().split_winid)
        t.eq(nil, helper.__state().split_tabpage)
        t.eq(nil, helper.__state().current_response_id)

        vim.cmd("normal! \27")
      end,
    },
    {
      name = "next closes the pane at the end of the queue",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/navigate.lua"
        t.write(file, "local one = 1\nlocal two = 2\n")
        local buf = t.new_buffer({
          "local one = 1",
          "local two = 2",
        }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })
        vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end)

        t.set_visual_marks(buf, 2, 1, 2, 13)
        helper.explain_visual({
          additional_prompt = "Question two",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 2
        end))

        helper.next_response()
        t.ok(helper.__state().split_winid ~= nil)
        t.eq({ 1, 0 }, vim.api.nvim_win_get_cursor(helper.__state().split_winid))
        helper.next_response()
        t.eq(nil, helper.__state().split_winid)
        t.eq(nil, helper.__state().current_response_id)
      end,
    },
    {
      name = "quitting response pane opens the next ready response",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/quit_handoff.lua"
        t.write(file, "local one = 1\nlocal two = 2\n")
        local buf = t.new_buffer({
          "local one = 1",
          "local two = 2",
        }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })
        vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end)
        local first_id = helper.__state().current_response_id

        t.set_visual_marks(buf, 2, 1, 2, 13)
        helper.explain_visual({
          additional_prompt = "Question two",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 2
        end))

        local entries = require("code_reviewer_helper.history").list()
        local second_id = entries[2].id
        t.eq(first_id, helper.__state().current_response_id)

        vim.api.nvim_win_call(helper.__state().split_winid, function()
          vim.cmd("quit")
        end)

        t.ok(vim.wait(2000, function()
          return helper.__state().current_response_id == second_id
        end))
        t.eq(second_id, helper.__state().current_response_id)
        t.ok(helper.__state().split_winid ~= nil)
      end,
    },
    {
      name = "quitting response pane does not open the next response outside the original tab",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/tab_handoff.lua"
        t.write(file, "local one = 1\nlocal two = 2\n")
        local buf = t.new_buffer({
          "local one = 1",
          "local two = 2",
        }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })
        t.ok(vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end))

        t.set_visual_marks(buf, 2, 1, 2, 13)
        helper.explain_visual({
          additional_prompt = "Question two",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 2
        end))

        vim.cmd("tabnew")
        local other_tab = vim.api.nvim_get_current_tabpage()
        t.new_buffer({ "other tab" }, root .. "/other.lua")
        vim.cmd("tabprevious")

        vim.cmd("tabclose")

        t.ok(vim.wait(2000, function()
          return vim.api.nvim_get_current_tabpage() == other_tab
        end))
        t.eq(nil, helper.__state().split_winid)
        t.eq(nil, helper.__state().split_tabpage)
        t.eq(nil, helper.__state().current_response_id)

        local buffer_names = {}
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            table.insert(buffer_names, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
          end
        end
        t.ok(not table.concat(buffer_names, "\n"):match("crh://response/"))
      end,
    },
    {
      name = "quitting response pane in visual mode does not open the next response",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/insert_handoff.lua"
        t.write(file, "local one = 1\nlocal two = 2\n")
        local buf = t.new_buffer({
          "local one = 1",
          "local two = 2",
        }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })
        t.ok(vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end))

        t.set_visual_marks(buf, 2, 1, 2, 13)
        helper.explain_visual({
          additional_prompt = "Question two",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 2
        end))

        vim.cmd("normal! v")
        t.eq(true, vim.wait(2000, function()
          return not require("code_reviewer_helper.util").mode_is_normal()
        end))

        vim.api.nvim_win_close(helper.__state().split_winid, true)

        t.wait(200)
        t.eq(nil, helper.__state().split_winid)
        t.eq(nil, helper.__state().split_tabpage)
        t.eq(nil, helper.__state().current_response_id)
        t.ok(not require("code_reviewer_helper.ui.split").is_open())

        vim.cmd("normal! \27")
      end,
    },
    {
      name = "reopening a closed response pane does not hit buffer name collisions",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/reopen.lua"
        t.write(file, "local one = 1\n")
        local buf = t.new_buffer({ "local one = 1" }, file)

        t.set_visual_marks(buf, 1, 1, 1, 13)
        helper.explain_visual({
          additional_prompt = "Question one",
        })
        t.ok(vim.wait(2000, function()
          return helper.__state().current_response_id ~= nil
        end))

        local first_id = helper.__state().current_response_id
        helper.next_response()
        t.eq(nil, helper.__state().split_winid)

        local ok, err = pcall(function()
          helper.open_last()
        end)
        if not ok then
          error(err)
        end

        t.eq(first_id, helper.__state().current_response_id)
        t.ok(helper.__state().split_winid ~= nil)
      end,
    },
    {
      name = "selection preview is truncated to 1000 characters with ellipsis",
      run = function()
        local helper, root = helper_with_config()
        local file = root .. "/preview.lua"
        local long_line = string.rep("x", 1100)
        t.write(file, long_line .. "\n")
        local buf = t.new_buffer({ long_line }, file)

        t.set_visual_marks(buf, 1, 1, 1, 1100)
        helper.explain_visual({
          additional_prompt = "Preview length",
        })
        t.ok(vim.wait(2000, function()
          local entries = require("code_reviewer_helper.history").list()
          return #entries == 1
        end))

        local entries = require("code_reviewer_helper.history").list()
        t.eq(1003, #entries[1].selection_preview)
        t.match("%.%.%.$", entries[1].selection_preview)
      end,
    },
    {
      name = "cancel stops active request",
      run = function()
        local helper, root = helper_with_config({
          codex = {
            bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_sleep.sh",
          },
        })
        local file = root .. "/demo.lua"
        t.write(file, "local x = 1\n")
        local buf = t.new_buffer({ "local x = 1" }, file)
        t.set_visual_marks(buf, 1, 1, 1, 11)

        helper.explain_visual({
          additional_prompt = "Explain sleep",
        })
        vim.wait(200, function()
          return next(helper.__state().active_jobs) ~= nil
        end)

        local cancelled = helper.cancel()
        t.eq(true, cancelled)
        t.eq(nil, next(helper.__state().active_jobs))
      end,
    },
    {
      name = "config normalizes guide defaults",
      run = function()
        local config = require("code_reviewer_helper.config").normalize({})
        t.eq(true, config.guide.persist)
        t.eq(30, config.guide.max_sessions)
        t.eq(20, config.guide.repo_mode_max_files)
        t.eq(true, config.guide.include_untracked)
      end,
    },
    {
      name = "guide prompt includes repo inventory and changed file metadata",
      run = function()
        local prompt = require("code_reviewer_helper.guide.prompt").build({
          workspace_root = "/tmp/project",
          mode = "changes",
          docs = {
            {
              relative_path = "README.md",
              content = "hello",
            },
          },
          inventory = {
            { path = "README.md", kind = "docs" },
            { path = "lua/code_reviewer_helper/init.lua", kind = "source" },
          },
          changes = {
            status_lines = { " M modified.lua" },
            diff_stat = " modified.lua | 2 +-",
            items = {
              {
                path = "modified.lua",
                status = "modified",
                diff_excerpt = "@@ -1 +1 @@",
                stats = { additions = 1, deletions = 1 },
              },
            },
          },
        }, {
          guide = { repo_mode_max_files = 20 },
        })
        t.match("Return exactly two sections", prompt)
        t.match("Repository Inventory", prompt)
        t.match("Changed File Excerpts", prompt)
        t.match("Every item path must exactly match", prompt)
        t.match("modified.lua", prompt)
      end,
    },
    {
      name = "guide parser accepts valid response and rejects malformed output",
      run = function()
        local parser = require("code_reviewer_helper.guide.parser")
        local parsed, err = parser.parse([[
```json
{"mode":"repo","summary":"demo","items":[{"path":"README.md","reason":"first","status":"repo","old_path":null}]}
```
# Review Order

1. README
        ]], {
          valid_paths = { ["README.md"] = true },
        })
        t.eq(nil, err)
        t.eq("repo", parsed.mode)
        t.eq("demo", parsed.summary)
        t.eq(1, #parsed.items)

        local recovered
        recovered, err = parser.parse([[
```json
{"mode":"repo","summary":"demo","items":[{"path":"README.md","reason":"first","status":"repo","old_path":null}]}
# Review Order

1. README
        ]], {
          valid_paths = { ["README.md"] = true },
        })
        t.eq(nil, err)
        t.eq("repo", recovered.mode)
        t.eq("demo", recovered.summary)
        t.eq(1, #recovered.items)
        t.match("# Review Order", recovered.plan_markdown)

        local invalid, err = parser.parse("nope", {
          valid_paths = {},
        })
        t.eq(nil, invalid)
        t.match("missing fenced json block", err)
      end,
    },
    {
      name = "guide auto-selects repo mode when repo is clean",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh"
        local helper, root = helper_with_guide_config(fake_bin)
        seed_repo_workspace(root)
        commit_all(root, "seed")

        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local session = helper.__state().guide_session
        t.eq("repo", session.mode)
        t.eq(3, #session.items)
        t.match("README.md", session.plan_markdown)
      end,
    },
    {
      name = "guide auto-selects changes mode when git status is non-empty",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_changes.sh"
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_changes_workspace(root)

        t.new_buffer({ "local value = 2", "return value" }, root .. "/modified.lua")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local session = helper.__state().guide_session
        t.eq("changes", session.mode)
        t.eq(4, #session.items)
        t.eq("modified.lua", session.items[1].path)
        t.eq("renamed_old.lua", session.items[4].old_path)
      end,
    },
    {
      name = "guide falls back to repo mode when no git root is available",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh"
        local helper = t.load_helper()
        local root = t.tmp_dir("nogit_workspace")
        seed_repo_workspace(root)

        helper.setup({
          codex = {
            bin = fake_bin,
            use_web_search = false,
          },
          btca = {
            sandbox_dir = t.tmp_dir("nogit_btca"),
            skill_path = t.tmp_dir("nogit_skill") .. "/SKILL.md",
          },
          history = {
            persist = false,
          },
          guide = {
            persist = false,
            use_diffview_if_available = false,
          },
        })

        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        t.eq("repo", helper.__state().guide_session.mode)
        t.eq(root, helper.__state().guide_session.workspace_root)
      end,
    },
    {
      name = "native guide UI opens list and supports next prev navigation",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh"
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        t.ok(helper.__state().guide_list_bufnr ~= nil)
        t.eq(1, helper.__state().guide_current_index)

        local guide_ui = require("code_reviewer_helper.ui.guide")
        guide_ui.next_item()
        t.eq(2, helper.__state().guide_current_index)
        guide_ui.prev_item()
        t.eq(1, helper.__state().guide_current_index)

        local guide_tabpage = helper.__state().guide_tabpage
        local guide_wins = vim.api.nvim_tabpage_list_wins(guide_tabpage)
        local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        local code_win = nil
        for _, win in ipairs(guide_wins) do
          if win ~= list_win then
            code_win = win
            break
          end
        end
        t.ok(list_win ~= nil)
        t.ok(code_win ~= nil)

        local list_col = vim.api.nvim_win_get_position(list_win)[2]
        local code_col = vim.api.nvim_win_get_position(code_win)[2]
        t.ok(list_col < code_col)

        local total_width = vim.api.nvim_win_get_width(list_win) + vim.api.nvim_win_get_width(code_win)
        local ratio = vim.api.nvim_win_get_width(list_win) / total_width
        t.ok(ratio > 0.18 and ratio < 0.3, string.format("unexpected list ratio: %.3f", ratio))

        vim.api.nvim_set_current_win(vim.fn.bufwinid(helper.__state().guide_list_bufnr))
        local mapping = vim.fn.maparg("<Tab>", "n", false, true)
        t.eq("<Tab>", mapping.lhs)
      end,
    },
    {
      name = "closing the explainer split restores the guide 20 80 layout",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local history = require("code_reviewer_helper.history")
        history.load(root, helper.__state().config.history)
        history.add({
          id = "guide-response",
          status = "success",
          summary = "Explain this",
          question = "Explain this",
          path = "README.md",
          filetype = "markdown",
          range = {
            start_row = 1,
            start_col = 1,
            end_row = 1,
            end_col = 6,
          },
          selection_preview = "# Demo",
          response_markdown = "Stub explanation",
          created_at = "2026-04-20T00:00:00Z",
          completed_at = "2026-04-20T00:00:01Z",
        })

        helper.open_last()
        t.ok(helper.__state().split_winid ~= nil)

        require("code_reviewer_helper.ui.split").close()
        t.ok(vim.wait(1000, function()
          if helper.__state().split_winid ~= nil then
            return false
          end

          local guide_tabpage = helper.__state().guide_tabpage
          local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
          local code_win = nil
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
            if win ~= list_win then
              code_win = win
              break
            end
          end

          if not list_win or not code_win then
            return false
          end

          local total_width = vim.api.nvim_win_get_width(list_win) + vim.api.nvim_win_get_width(code_win)
          local ratio = vim.api.nvim_win_get_width(list_win) / total_width
          return ratio > 0.18 and ratio < 0.3
        end))

        local guide_tabpage = helper.__state().guide_tabpage
        local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        local code_win = nil
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
          if win ~= list_win then
            code_win = win
            break
          end
        end

        t.ok(list_win ~= nil)
        t.ok(code_win ~= nil)
        local total_width = vim.api.nvim_win_get_width(list_win) + vim.api.nvim_win_get_width(code_win)
        local ratio = vim.api.nvim_win_get_width(list_win) / total_width
        t.ok(ratio > 0.18 and ratio < 0.3, string.format("unexpected list ratio after close: %.3f", ratio))
      end,
    },
    {
      name = "handoff to the next explainer response preserves the three-pane layout",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local guide_tabpage = helper.__state().guide_tabpage
        local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        local code_win = nil
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
          if win ~= list_win then
            code_win = win
            break
          end
        end
        t.ok(code_win ~= nil)
        vim.api.nvim_set_current_win(code_win)

        local history = require("code_reviewer_helper.history")
        history.load(root, helper.__state().config.history)
        history.add({
          id = "guide-response-one",
          status = "success",
          summary = "Explain this",
          question = "Explain this",
          path = "README.md",
          filetype = "markdown",
          range = {
            start_row = 1,
            start_col = 1,
            end_row = 1,
            end_col = 6,
          },
          selection_preview = "# Demo",
          response_markdown = "Stub explanation one",
          created_at = "2026-04-20T00:00:00Z",
          completed_at = "2026-04-20T00:00:01Z",
        })
        history.add({
          id = "guide-response-two",
          status = "success",
          summary = "Explain this again",
          question = "Explain this again",
          path = "README.md",
          filetype = "markdown",
          range = {
            start_row = 1,
            start_col = 1,
            end_row = 1,
            end_col = 6,
          },
          selection_preview = "# Demo",
          response_markdown = "Stub explanation two",
          created_at = "2026-04-20T00:00:02Z",
          completed_at = "2026-04-20T00:00:03Z",
        })

        require("code_reviewer_helper.ui.split").render(history.list()[1], helper.__state().config)
        t.ok(helper.__state().split_winid ~= nil)
        local split_width_before = vim.api.nvim_win_get_width(helper.__state().split_winid)
        local list_width_before = vim.api.nvim_win_get_width(list_win)
        local code_width_before = vim.api.nvim_win_get_width(code_win)

        vim.api.nvim_win_call(helper.__state().split_winid, function()
          vim.cmd("quit")
        end)

        t.ok(vim.wait(1000, function()
          return helper.__state().current_response_id == "guide-response-two"
        end))

        guide_tabpage = helper.__state().guide_tabpage
        list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        code_win = nil
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
          if win ~= list_win and win ~= helper.__state().split_winid then
            code_win = win
            break
          end
        end

        t.ok(list_win ~= nil)
        t.ok(code_win ~= nil)
        t.ok(helper.__state().split_winid ~= nil)
        t.ok(math.abs(vim.api.nvim_win_get_width(helper.__state().split_winid) - split_width_before) <= 2)
        t.ok(math.abs(vim.api.nvim_win_get_width(list_win) - list_width_before) <= 2)
        t.ok(math.abs(vim.api.nvim_win_get_width(code_win) - code_width_before) <= 2)
      end,
    },
    {
      name = "changed-file fallback renders modified untracked deleted and renamed entries",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_changes.sh"
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_changes_workspace(root)
        t.new_buffer({ "local value = 2", "return value" }, root .. "/modified.lua")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local guide_ui = require("code_reviewer_helper.ui.guide")
        local bufs = current_tab_content_buffers()
        t.eq(3, #bufs)

        local modified_left = find_buffer_by_name("crh://guide%-left/")
        local modified_text = table.concat(vim.api.nvim_buf_get_lines(modified_left, 0, -1, false), "\n")
        t.match("local value = 1", modified_text)
        local modified_right = vim.fn.bufnr(root .. "/modified.lua")
        t.ok(modified_right ~= -1)
        t.eq(true, vim.bo[modified_right].modifiable)

        local guide_tabpage = helper.__state().guide_tabpage
        local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        local positions = {}
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
          positions[#positions + 1] = {
            win = win,
            col = vim.api.nvim_win_get_position(win)[2],
            width = vim.api.nvim_win_get_width(win),
          }
        end
        table.sort(positions, function(a, b)
          return a.col < b.col
        end)
        t.ok(list_win ~= nil)
        t.eq(list_win, positions[1].win)
        t.ok(positions[1].col < positions[2].col)
        t.ok(math.abs(positions[2].width - positions[3].width) <= 2)

        guide_ui.next_item()
        local untracked_left_buf = find_buffer_by_name("crh://guide%-left/")
        local untracked_left = table.concat(vim.api.nvim_buf_get_lines(untracked_left_buf, 0, -1, false), "\n")
        t.match("No file on left side", untracked_left)

        guide_ui.next_item()
        local deleted_right_buf = find_buffer_by_name("crh://guide%-right/")
        local deleted_right = table.concat(vim.api.nvim_buf_get_lines(deleted_right_buf, 0, -1, false), "\n")
        t.match("No file on right side", deleted_right)

        guide_ui.next_item()
        local renamed_left_buf = find_buffer_by_name("crh://guide%-left/")
        local renamed_left = table.concat(vim.api.nvim_buf_get_lines(renamed_left_buf, 0, -1, false), "\n")
        t.match("old", renamed_left)
      end,
    },
    {
      name = "diffview integration receives files in agent order when installed",
      run = function()
        local guide_ui = require("code_reviewer_helper.ui.guide")
        local added
        local opened = false

        package.loaded["diffview.rev"] = {
          Rev = function(kind, value)
            return { kind = kind, value = value }
          end,
          RevType = {
            COMMIT = "commit",
            LOCAL = "local",
          },
        }
        package.loaded["diffview.api.views.diff.diff_view"] = {
          CDiffView = function(opts)
            return {
              opts = opts,
              open = function(self)
                opened = true
                vim.cmd("tabnew")
              end,
            }
          end,
        }
        package.loaded["diffview.lib"] = {
          add_view = function(view)
            added = view
          end,
        }

        local session = {
          id = "guide-diffview",
          mode = "changes",
          workspace_root = t.tmp_dir("diffview_repo"),
          summary = "demo",
          plan_markdown = "# Review Order\n",
          items = {
            { path = "b.lua", reason = "second", status = "modified" },
            { path = "a.lua", reason = "first", status = "untracked" },
          },
        }

        guide_ui.open(session, {
          guide = {
            use_diffview_if_available = true,
          },
        })

        t.ok(opened)
        t.eq("b.lua", added.opts.files.working[1].path)
        t.eq("a.lua", added.opts.files.working[2].path)
        t.eq(nil, added.opts.get_file_data("working", "b.lua", "right"))

        package.loaded["diffview.rev"] = nil
        package.loaded["diffview.api.views.diff.diff_view"] = nil
        package.loaded["diffview.lib"] = nil
      end,
    },
    {
      name = "reopening a guide session refreshes buffers without duplicate-name errors",
      run = function()
        local guide_ui = require("code_reviewer_helper.ui.guide")
        local state = require("code_reviewer_helper.state")
        local root = t.tmp_dir("guide_reopen")
        local config = {
          guide = {
            use_diffview_if_available = false,
          },
        }
        local original_devicons = package.loaded["nvim-web-devicons"]

        package.loaded["nvim-web-devicons"] = {
          get_icon = function()
            return "X"
          end,
        }

        guide_ui.open({
          id = "guide-one",
          mode = "repo",
          workspace_root = root,
          summary = "first summary",
          plan_markdown = "# Review Order\n\n1. first",
          items = {
            { path = "README.md", reason = "first reason", status = "repo" },
          },
        }, config)

        local ok, err = pcall(function()
          guide_ui.open({
            id = "guide-two",
            mode = "repo",
            workspace_root = root,
            summary = "second summary",
            plan_markdown = "# Review Order\n\n1. second",
            items = {
              { path = "lua/code_reviewer_helper/init.lua", reason = "second reason", status = "repo" },
            },
          }, config)
        end)

        package.loaded["nvim-web-devicons"] = original_devicons

        t.ok(ok, err)
        local list_text = table.concat(vim.api.nvim_buf_get_lines(state.guide_list_bufnr, 0, -1, false), "\n")
        local plan_text = table.concat(vim.api.nvim_buf_get_lines(state.guide_plan_bufnr, 0, -1, false), "\n")
        t.match("second summary", list_text)
        t.match("X lua/code_reviewer_helper/init.lua", list_text)
        t.match("1%. second", plan_text)
      end,
    },
    {
      name = "guide plan command reopens the persisted plan buffer",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh"
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        helper.open_guide_plan()

        local plan_buf = helper.__state().guide_plan_bufnr
        t.ok(plan_buf ~= nil)
        local text = table.concat(vim.api.nvim_buf_get_lines(plan_buf, 0, -1, false), "\n")
        t.match("# Review Order", text)
      end,
    },
    {
      name = "guide request sanitizes invalid UTF-8 in prompt sources",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        t.write(root .. "/README.md", "# Demo\n" .. string.char(255) .. "\n")
        t.write(root .. "/plugin/code_reviewer_helper.lua", "return {}\n")
        t.write(root .. "/lua/code_reviewer_helper/init.lua", "return {}\n")
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        t.eq("repo", helper.__state().guide_session.mode)
      end,
    },
    {
      name = "guide request succeeds when codex rejects non-UTF-8 stdin",
      run = function()
        local helper, root = helper_with_guide_config(make_utf8_validating_fake_bin(), {
          guide = {
            use_diffview_if_available = false,
          },
        })
        t.write(root .. "/README.md", "# Demo\n" .. string.char(255) .. "\n")
        t.write(root .. "/plugin/code_reviewer_helper.lua", "return {}\n")
        t.write(root .. "/lua/code_reviewer_helper/init.lua", "return {}\n")
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        t.eq("repo", helper.__state().guide_session.mode)
      end,
    },
    {
      name = "guide history labels include the commit subject",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local seen_label
        local original_select = vim.ui.select
        vim.ui.select = function(items, opts, callback)
          seen_label = items[1].label
          callback(nil)
        end

        require("code_reviewer_helper.ui.guide_history").pick(function() end)
        vim.ui.select = original_select

        t.match("seed", seen_label or "")
      end,
    },
    {
      name = "guide history can be cleared",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              persist = true,
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))
        local history_path = helper.__state().guide_history.path

        t.ok(helper.clear_guide_history())
        t.eq(0, #require("code_reviewer_helper.guide.history").list())
        t.eq(false, require("code_reviewer_helper.util").file_exists(history_path))
      end,
    },
    {
      name = "opening guide history restores the original file when the guide closes",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")

        local review_path = root .. "/plugin/code_reviewer_helper.lua"
        local review_buf = t.new_buffer({ "return {}", "-- marker" }, review_path)
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        local sessions = require("code_reviewer_helper.guide.history").load(root, helper.__state().config.guide)
        table.insert(sessions.entries, {
          id = "saved-guide",
          mode = "repo",
          workspace_root = root,
          summary = "saved summary",
          plan_markdown = "# Review Order\n\n1. README.md",
          items = {
            { path = "README.md", reason = "start here", status = "repo" },
          },
          created_at = "2026-04-20T00:00:00Z",
        })

        local original_select = vim.ui.select
        vim.ui.select = function(items, opts, callback)
          callback(items[1])
        end

        local ok, err = pcall(function()
          helper.open_guide_history()
        end)
        vim.ui.select = original_select
        if not ok then
          error(err)
        end

        t.ok(wait_for_guide_session(helper))
        require("code_reviewer_helper.ui.guide").close()

        t.eq(review_buf, vim.api.nvim_get_current_buf())
        t.eq(review_path, vim.api.nvim_buf_get_name(0))
        t.eq({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
      end,
    },
    {
      name = "closing a guide saves the current file and reopening resumes there",
      run = function()
        local helper, root = helper_with_guide_config(
          "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_repo.sh",
          {
            guide = {
              use_diffview_if_available = false,
            },
          }
        )
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local guide_ui = require("code_reviewer_helper.ui.guide")
        guide_ui.next_item()
        local session = helper.__state().guide_session
        local expected_path = session.items[2].path

        t.ok(helper.close_guide())
        t.eq(2, session.resume_index)
        t.eq(expected_path, session.resume_path)

        helper.open_last_guide()
        t.eq(2, helper.__state().guide_current_index)

        local guide_tabpage = helper.__state().guide_tabpage
        local list_win = find_win_for_buf(guide_tabpage, helper.__state().guide_list_bufnr)
        local content_win = nil
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(guide_tabpage)) do
          if win ~= list_win then
            content_win = win
            break
          end
        end

        t.ok(content_win ~= nil)
        t.match(expected_path .. "$", vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(content_win)))
      end,
    },
    {
      name = "invalid guide response opens a parse failure buffer and does not create a session",
      run = function()
        local fake_bin = "/home/automac/Documents/Projects/code-reviewer-helper/tests/fakes/codex_guide_invalid.sh"
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        vim.wait(2000, function()
          local lines = vim.api.nvim_buf_get_lines(0, 0, 1, false)
          return lines[1] == "# Guide Parse Failure"
        end)

        t.eq(nil, helper.__state().guide_session)
        local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        t.match("Guide Parse Failure", text)
      end,
    },
    {
      name = "guide retries once when parser rejects foreign repo paths",
      run = function()
        local fake_bin, counter = make_retry_fake_bin()
        local helper, root = helper_with_guide_config(fake_bin, {
          guide = {
            use_diffview_if_available = false,
          },
        })
        seed_repo_workspace(root)
        commit_all(root, "seed")
        t.new_buffer({ "# Demo" }, root .. "/README.md")

        helper.guide()
        t.ok(wait_for_guide_session(helper))

        local session = helper.__state().guide_session
        t.eq("repo", session.mode)
        t.eq(2, #session.items)
        t.eq("README.md", session.items[1].path)
        t.eq("2", t.read(counter))
      end,
    },
  }
end

return M
