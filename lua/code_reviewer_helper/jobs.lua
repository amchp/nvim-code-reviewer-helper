local history = require("code_reviewer_helper.history")
local provider = require("code_reviewer_helper.provider.codex_exec")
local split = require("code_reviewer_helper.ui.split")
local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}
local SELECTION_PREVIEW_LIMIT = 1000

local function timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function next_id()
  return tostring(vim.uv.hrtime())
end

local function active_count()
  local count = 0
  for _ in pairs(state.active_jobs) do
    count = count + 1
  end
  return count
end

local function selection_preview(selection)
  if not selection or not selection.selected_lines then
    return ""
  end
  local preview = table.concat(selection.selected_lines, "\n")
  if #preview <= SELECTION_PREVIEW_LIMIT then
    return preview
  end
  return preview:sub(1, SELECTION_PREVIEW_LIMIT) .. "..."
end

function M.submit(payload, config)
  local id = next_id()
  local request = {
    id = id,
    prompt = payload.prompt,
    workspace_root = payload.workspace_root,
  }
  local job_state = {
    cancelled = false,
  }

  local job = provider.submit(request, config, {
    on_complete = function(result)
      if job_state.cancelled then
        util.remove_file(result.output_path)
        return
      end

      local response = util.read_file(result.output_path) or ""
      local status = result.code == 0 and "success" or "failed"
      if response == "" and status == "failed" then
        response = "Codex request failed before producing a final message."
      end

      local entry = {
        id = id,
        status = status,
        summary = payload.question,
        question = payload.question,
        path = payload.selection.path,
        filetype = payload.selection.filetype,
        range = payload.selection.range,
        selection_preview = selection_preview(payload.selection),
        response_markdown = response,
        stderr = result.stderr,
        exit_code = result.code,
        created_at = payload.created_at,
        completed_at = timestamp(),
      }

      state.active_jobs[id] = nil
      history.add(entry)
      if not split.is_open() and split.should_auto_open() then
        split.render(entry, config, {
          focus = false,
          prefer_anchor = true,
        })
      end

      if status == "success" then
        util.notify(
          string.format(
            "Explain request %s completed. Active requests: %d",
            id,
            active_count()
          )
        )
      else
        util.notify(
          string.format(
            "Explain request %s failed. Active requests: %d",
            id,
            active_count()
          ),
          vim.log.levels.ERROR
        )
      end

      util.remove_file(result.output_path)
    end,
  })

  job.cancelled = job_state
  state.active_jobs[id] = job
  util.notify(
    string.format(
      "Queued explain request %s. Active requests: %d",
      id,
      active_count()
    )
  )
  return id
end

function M.cancel(id)
  local target_id = id
  if not target_id then
    for key in pairs(state.active_jobs) do
      target_id = key
      break
    end
  end

  if not target_id or not state.active_jobs[target_id] then
    util.notify("No active request to cancel", vim.log.levels.WARN)
    return false
  end

  state.active_jobs[target_id].cancelled.cancelled = true
  provider.cancel(state.active_jobs[target_id])
  state.active_jobs[target_id] = nil
  util.notify(
    string.format(
      "Cancelled request %s. Active requests: %d",
      target_id,
      active_count()
    )
  )
  return true
end

return M
