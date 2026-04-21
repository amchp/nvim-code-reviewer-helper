local context_mod = require("code_reviewer_helper.guide.context")
local guide_history = require("code_reviewer_helper.guide.history")
local parser = require("code_reviewer_helper.guide.parser")
local prompt_mod = require("code_reviewer_helper.guide.prompt")
local provider = require("code_reviewer_helper.provider.codex_exec")
local state = require("code_reviewer_helper.state")
local ui = require("code_reviewer_helper.ui.guide")
local util = require("code_reviewer_helper.util")

local M = {}

local function timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function next_id()
  return tostring(vim.uv.hrtime())
end

local function resolve_workspace_seed()
  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" and vim.startswith(current, "crh://guide") and state.guide_session and state.guide_session.workspace_root then
    return state.guide_session.workspace_root
  end
  if current ~= "" then
    if util.is_dir(current) then
      return current
    end
    return vim.fn.fnamemodify(current, ":p:h")
  end
  return vim.uv.cwd()
end

local function current_return_target()
  local winid = vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local path = vim.api.nvim_buf_get_name(bufnr)

  return {
    winid = winid,
    tabpage = tabpage,
    bufnr = bufnr,
    path = path ~= "" and path or nil,
    cursor = vim.api.nvim_win_get_cursor(winid),
  }
end

local function commit_info(git_root)
  if not git_root then
    return nil
  end

  local commit = util.system({
    "git",
    "-C",
    git_root,
    "log",
    "-1",
    "--pretty=format:%H%n%h%n%s",
  })
  if commit.code ~= 0 then
    return nil
  end

  local lines = vim.split(commit.stdout or "", "\n", { plain = true })
  local branch = util.system({
    "git",
    "-C",
    git_root,
    "branch",
    "--show-current",
  })

  return {
    hash = lines[1] or "",
    short = lines[2] or "",
    subject = lines[3] or "",
    branch = util.trim(branch.stdout or ""),
  }
end

function M.ensure_history_loaded()
  local seed = resolve_workspace_seed()
  local root = util.git_root(seed) or seed
  if state.guide_history and state.guide_history.workspace_root == root then
    return state.guide_history
  end
  return guide_history.load(root, state.config.guide)
end

local function finalize_session(parsed, context)
  local session = {
    id = next_id(),
    mode = parsed.mode,
    workspace_root = context.workspace_root,
    summary = parsed.summary,
    plan_markdown = parsed.plan_markdown,
    items = parsed.items,
    commit = commit_info(context.git_root),
    resume_index = 1,
    resume_path = parsed.items[1] and parsed.items[1].path or nil,
    created_at = timestamp(),
  }

  guide_history.load(context.workspace_root, state.config.guide)
  guide_history.add(session)
  ui.open(session, state.config)
  util.notify(string.format("Guided review ready: %d files", #session.items))
  return session
end

function M.start()
  local seed = resolve_workspace_seed()
  local context = context_mod.build(seed, state.config)
  local prompt = prompt_mod.build(context, state.config)
  local request_id = next_id()

  state.active_guide_jobs[request_id] = provider.submit({
    id = request_id,
    prompt = prompt,
    workspace_root = context.workspace_root,
  }, state.config, {
    on_complete = function(result)
      state.active_guide_jobs[request_id] = nil
      local response = util.read_file(result.output_path) or ""
      util.remove_file(result.output_path)

      if result.code ~= 0 then
        ui.show_parse_failure(response ~= "" and response or result.stderr, "codex guide request failed")
        util.notify("Guided review request failed", vim.log.levels.ERROR)
        return
      end

      local parsed, err = parser.parse(response, context)
      if not parsed then
        ui.show_parse_failure(response, err)
        util.notify("Guided review parse failed: " .. err, vim.log.levels.ERROR)
        return
      end

      finalize_session(parsed, context)
    end,
  })

  util.notify(string.format("Queued guided review request %s", request_id))
  return request_id
end

function M.open(session, opts)
  opts = opts or {}
  state.guide_return_target = opts.capture_return_target and current_return_target() or nil
  ui.open(session, state.config)
end

function M.clear_history()
  local history = M.ensure_history_loaded()
  if not history then
    return false
  end
  return guide_history.clear()
end

function M.open_plan()
  return ui.open_plan()
end

return M
