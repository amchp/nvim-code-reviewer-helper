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
  if current ~= "" then
    if util.is_dir(current) then
      return current
    end
    return vim.fn.fnamemodify(current, ":p:h")
  end
  return vim.uv.cwd()
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
    created_at = timestamp(),
  }

  guide_history.load(context.workspace_root, state.config.guide)
  guide_history.add(session)
  state.guide_session = session
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

function M.open(session)
  state.guide_session = session
  ui.open(session, state.config)
end

function M.open_plan()
  return ui.open_plan()
end

return M
