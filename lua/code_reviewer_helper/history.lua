local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}

local function history_dir()
  return vim.fn.stdpath("state") .. "/code-reviewer-helper"
end

function M.path_for_workspace(workspace_root)
  return history_dir() .. "/" .. util.workspace_id(workspace_root) .. ".json"
end

function M.load(workspace_root, config)
  local path = M.path_for_workspace(workspace_root)
  local data = util.json_decode(util.read_file(path), { entries = {} })
  data.entries = data.entries or {}
  state.history = {
    workspace_root = workspace_root,
    path = path,
    entries = data.entries,
    config = config,
  }
  return state.history
end

function M.current()
  return state.history
end

function M.save()
  if not state.history or not state.history.config.persist then
    return
  end
  util.ensure_dir(history_dir())
  util.write_file(state.history.path, util.json_encode({
    entries = state.history.entries,
  }))
end

function M.add(entry)
  local history = state.history
  if not history then
    return
  end
  table.insert(history.entries, entry)
  while #history.entries > history.config.max_entries do
    table.remove(history.entries, 1)
  end
  M.save()
end

function M.find(id)
  if not state.history then
    return nil
  end
  for index, entry in ipairs(state.history.entries) do
    if entry.id == id then
      return entry, index
    end
  end
  return nil
end

function M.list()
  if not state.history then
    return {}
  end
  return state.history.entries
end

function M.neighbor(current_id, step)
  local _, index = M.find(current_id)
  if not index then
    return nil
  end
  local target = index + step
  return state.history.entries[target]
end

return M
