local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}

local function history_dir()
  return vim.fn.stdpath("state") .. "/code-reviewer-helper/guides"
end

function M.path_for_workspace(workspace_root)
  return history_dir() .. "/" .. util.workspace_id(workspace_root) .. ".json"
end

function M.load(workspace_root, config)
  local path = M.path_for_workspace(workspace_root)
  local data = util.json_decode(util.read_file(path), { entries = {} })
  data.entries = data.entries or {}
  state.guide_history = {
    workspace_root = workspace_root,
    path = path,
    entries = data.entries,
    config = config,
  }
  return state.guide_history
end

function M.current()
  return state.guide_history
end

function M.save()
  if not state.guide_history or not state.guide_history.config.persist then
    return
  end

  util.ensure_dir(history_dir())
  util.write_file(state.guide_history.path, util.json_encode({
    entries = state.guide_history.entries,
  }))
end

function M.add(entry)
  local history = state.guide_history
  if not history then
    return
  end

  table.insert(history.entries, entry)
  while #history.entries > history.config.max_sessions do
    table.remove(history.entries, 1)
  end
  M.save()
end

function M.update(entry)
  local history = state.guide_history
  if not history or not entry or not entry.id then
    return false
  end

  for index, existing in ipairs(history.entries) do
    if existing.id == entry.id then
      history.entries[index] = entry
      M.save()
      return true
    end
  end

  return false
end

function M.clear()
  local history = state.guide_history
  if not history then
    return false
  end

  history.entries = {}
  if history.config.persist then
    pcall(vim.uv.fs_unlink, history.path)
  end
  return true
end

function M.list()
  if not state.guide_history then
    return {}
  end
  return state.guide_history.entries
end

function M.find(id)
  if not state.guide_history then
    return nil
  end

  for index, entry in ipairs(state.guide_history.entries) do
    if entry.id == id then
      return entry, index
    end
  end

  return nil
end

return M
