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

local function previous_commit_objects(git_root, count)
  if not git_root then
    return {}
  end
  local result = util.system({
    "git",
    "-C",
    git_root,
    "log",
    "-" .. tostring(count or 5),
    "--pretty=format:%H%x09%h%x09%s",
  })
  if result.code ~= 0 then
    return {}
  end
  local commits = {}
  for _, line in ipairs(vim.split(util.trim(result.stdout or ""), "\n", { plain = true })) do
    local hash, short, subject = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
    if short and short ~= "" then
      table.insert(commits, {
        hash = hash,
        short = short,
        subject = subject or "",
      })
    end
  end
  return commits
end

local function overview_item()
  return {
    kind = "overview",
    path = "__overview__",
    reason = "Review Overview",
    status = "overview",
    old_path = nil,
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
  local items = vim.deepcopy(parsed.items)
  table.insert(items, 1, overview_item())
  local session = {
    id = next_id(),
    mode = parsed.mode,
    workspace_root = context.workspace_root,
    summary = parsed.summary,
    overview_markdown = parsed.overview_markdown,
    plan_markdown = parsed.plan_markdown,
    items = items,
    commit = commit_info(context.git_root),
    base_rev = context.changes and context.changes.base_rev or nil,
    commit_count = context.changes and context.changes.commit_count or nil,
    selected_commits = context.selected_commits,
    diff_stat = context.changes and context.changes.diff_stat or nil,
    uncommitted_included = context.changes and context.changes.uncommitted_included or false,
    resume_index = 1,
    resume_path = "__overview__",
    created_at = timestamp(),
  }

  guide_history.load(context.workspace_root, state.config.guide)
  guide_history.add(session)
  ui.open(session, state.config)
  util.notify(string.format("Review Session ready: %d items", #session.items))
  return session
end

local function handle_completion(request_id, context, attempt, result)
  state.active_guide_jobs[request_id] = nil
  local response = util.read_file(result.output_path) or ""
  util.remove_file(result.output_path)

  if result.code ~= 0 then
    ui.show_parse_failure(response ~= "" and response or result.stderr, "codex Review Session request failed")
    util.notify("Review Session request failed", vim.log.levels.ERROR)
    return
  end

  local parsed, err = parser.parse(response, context)
  if parsed then
    finalize_session(parsed, context)
    return
  end

  if attempt < 2 then
    local repair_id = next_id()
    local repair_prompt = prompt_mod.build_repair(context, state.config, response, err)
    util.notify("Review Session response invalid, retrying once", vim.log.levels.WARN)
    state.active_guide_jobs[repair_id] = provider.submit({
      id = repair_id,
      prompt = repair_prompt,
      workspace_root = context.workspace_root,
    }, state.config, {
      on_complete = function(repair_result)
        handle_completion(repair_id, context, attempt + 1, repair_result)
      end,
    })
    return
  end

  ui.show_parse_failure(response, err)
  util.notify("Review Session parse failed: " .. err, vim.log.levels.ERROR)
end

function M.start(opts)
  opts = opts or {}
  local seed = resolve_workspace_seed()
  local context = context_mod.build(seed, state.config, opts)
  if context.error then
    util.notify(context.error, vim.log.levels.ERROR)
    return nil
  end
  local prompt = prompt_mod.build(context, state.config)
  local request_id = next_id()

  state.active_guide_jobs[request_id] = provider.submit({
    id = request_id,
    prompt = prompt,
    workspace_root = context.workspace_root,
  }, state.config, {
    on_complete = function(result)
      handle_completion(request_id, context, 1, result)
    end,
  })

  util.notify(string.format("Queued Review Session request %s", request_id))
  return request_id
end

function M.start_codebase()
  return M.start({ mode = "codebase" })
end

local function commit_count_prompt(git_root)
  local commits = previous_commit_objects(git_root, 5)
  local lines = { "Git Changes Review commit count N (HEAD~N to working tree)." }
  if #commits > 0 then
    table.insert(lines, "Previous 5 commits:")
    for _, commit in ipairs(commits) do
      table.insert(lines, string.format("%s %s", commit.short, commit.subject))
    end
  end
  table.insert(lines, "N: ")
  return table.concat(lines, "\n"), commits
end

local function parse_commit_count(input)
  local value = util.trim(input or "")
  if value == "" or not value:match("^%d+$") then
    return nil
  end
  local count = tonumber(value)
  if not count or count < 1 then
    return nil
  end
  return count
end

function M.start_git_changes(commit_count)
  local seed = resolve_workspace_seed()
  local git_root = util.git_root(seed)
  if not git_root then
    util.notify("Git Changes Review requires a git repository", vim.log.levels.ERROR)
    return nil
  end

  local prompt, commits = commit_count_prompt(git_root)
  local function start_with_count(input)
    local count = parse_commit_count(input)
    if not count then
      util.notify("Git Changes Review canceled: enter a positive integer commit count.", vim.log.levels.WARN)
      return nil
    end
    return M.start({
      mode = "git_changes",
      commit_count = count,
      selected_commits = commits,
    })
  end

  if commit_count ~= nil then
    return start_with_count(tostring(commit_count))
  end

  vim.ui.input({
    prompt = prompt,
  }, function(input)
    if input == nil then
      return
    end
    start_with_count(input)
  end)
  return nil
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
