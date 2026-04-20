local btca = require("code_reviewer_helper.btca")
local config_mod = require("code_reviewer_helper.config")
local context_mod = require("code_reviewer_helper.context")
local guide_history_ui = require("code_reviewer_helper.ui.guide_history")
local guide_session = require("code_reviewer_helper.guide.session")
local health_mod = require("code_reviewer_helper.health")
local history = require("code_reviewer_helper.history")
local jobs = require("code_reviewer_helper.jobs")
local prompt_mod = require("code_reviewer_helper.prompt")
local selection_mod = require("code_reviewer_helper.selection")
local split = require("code_reviewer_helper.ui.split")
local history_ui = require("code_reviewer_helper.ui.history")
local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}

local function ensure_setup()
  if not state.config then
    M.setup()
  end
end

local function ensure_history_loaded()
  if state.history then
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  local root = util.git_root(path ~= "" and path or vim.uv.cwd()) or vim.uv.cwd()
  history.load(root, state.config.history)
end

local function ensure_workspace_history(workspace_root)
  if state.history and state.history.workspace_root == workspace_root then
    return state.history
  end
  return history.load(workspace_root, state.config.history)
end

local function question_or_default(input, config)
  local trimmed = util.trim(input)
  if trimmed == "" then
    return config.prompt.default_question
  end
  return trimmed
end

local function capture_selection_or_notify(config)
  local selection, err = selection_mod.capture({
    require_visual_mode = config.prompt.require_visual_mode,
    allow_marks = true,
    max_selection_lines = config.context.max_selection_lines,
    surrounding_lines = config.context.surrounding_lines,
    include_diagnostics = config.context.include_diagnostics,
    include_symbol_context = config.context.include_symbol_context,
  })

  if not selection then
    util.notify(err, vim.log.levels.ERROR)
    return nil
  end

  return selection
end

local function leave_visual_mode()
  if util.mode_is_visual() then
    vim.cmd("normal! \27")
  end
end

local function start_explain(question, opts, selection)
  ensure_setup()
  local config = state.config

  local context = context_mod.build(selection, config)
  ensure_workspace_history(context.workspace_root)

  local final_question = question_or_default(question, config)
  local prompt = prompt_mod.build(final_question, selection, context)

  return jobs.submit({
    question = final_question,
    selection = selection,
    workspace_root = context.workspace_root,
    prompt = prompt,
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }, config)
end

function M.setup(opts)
  state.config = config_mod.normalize(opts)
  if state.config.btca.enabled and state.config.btca.auto_sync then
    btca.sync(state.config.btca)
  end
  return state.config
end

function M.explain_visual(opts)
  opts = opts or {}
  ensure_setup()
  local selection = capture_selection_or_notify(state.config)
  if not selection then
    return nil
  end
  leave_visual_mode()
  if opts.additional_prompt ~= nil then
    return start_explain(opts.additional_prompt, opts, selection)
  end

  vim.ui.input({
    prompt = "Explain selection: ",
  }, function(input)
    if input == nil then
      return
    end
    start_explain(input, opts, selection)
  end)
  return nil
end

function M.open_history()
  ensure_setup()
  ensure_history_loaded()
  history_ui.pick(function(entry)
    split.render(entry, state.config)
  end)
end

function M.open_last()
  ensure_setup()
  ensure_history_loaded()
  local entries = history.list()
  if #entries == 0 then
    util.notify("No saved responses yet", vim.log.levels.INFO)
    return
  end
  split.render(entries[#entries], state.config)
end

function M.next_response()
  ensure_setup()
  ensure_history_loaded()
  if not split.is_open() then
    M.open_last()
    return
  end
  local entry = history.neighbor(state.current_response_id, 1)
  if not entry then
    split.close()
    util.notify("Reached the end of the response queue; closed the review pane", vim.log.levels.INFO)
    return
  end
  split.render(entry, state.config)
end

function M.prev_response()
  ensure_setup()
  ensure_history_loaded()
  if not split.is_open() then
    M.open_last()
    return
  end
  local entry = history.neighbor(state.current_response_id, -1)
  if not entry then
    util.notify("No previous response", vim.log.levels.INFO)
    return
  end
  split.render(entry, state.config)
end

function M.cancel(id)
  ensure_setup()
  return jobs.cancel(id)
end

function M.sync_btca()
  ensure_setup()
  local messages = btca.sync(state.config.btca)
  util.notify(table.concat(messages, "\n"))
  return messages
end

function M.health()
  ensure_setup()
  return health_mod.run(state.config)
end

function M.guide()
  ensure_setup()
  return guide_session.start()
end

function M.open_guide_history()
  ensure_setup()
  local sessions = guide_session.ensure_history_loaded()
  if not sessions or #sessions.entries == 0 then
    util.notify("No saved guide sessions yet", vim.log.levels.INFO)
    return
  end
  guide_history_ui.pick(function(entry)
    guide_session.open(entry)
  end)
end

function M.open_last_guide()
  ensure_setup()
  local sessions = guide_session.ensure_history_loaded()
  if not sessions or #sessions.entries == 0 then
    util.notify("No saved guide sessions yet", vim.log.levels.INFO)
    return
  end
  guide_session.open(sessions.entries[#sessions.entries])
end

function M.open_guide_plan()
  ensure_setup()
  return guide_session.open_plan()
end

function M.__state()
  return state
end

return M
