local util = require("code_reviewer_helper.util")

local M = {}

local fallback_prompt = [[
BTCA Local instructions:
- Search local git repositories cloned under the BTCA sandbox directory when useful.
- Prefer repository facts over guessing.
- Include citations to repository files and any web docs used.
- Keep explanations concrete and oriented around the selected code.
]]

local function repo_name(url)
  return url:match("/([^/]+)%.git$") or url:match("/([^/]+)$")
end

function M.skill_content(config)
  local data = util.read_file(config.skill_path)
  if data and data ~= "" then
    return data
  end
  if config.fallback_prompt then
    return fallback_prompt
  end
  return nil
end

function M.list_repositories(config)
  if not util.is_dir(config.sandbox_dir) then
    return {}
  end

  local handle = vim.uv.fs_scandir(config.sandbox_dir)
  if not handle then
    return {}
  end

  local repos = {}
  while true do
    local name = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local path = config.sandbox_dir .. "/" .. name
    if util.is_dir(path) and util.is_dir(path .. "/.git") then
      table.insert(repos, {
        name = name,
        path = path,
      })
    end
  end

  table.sort(repos, function(left, right)
    return left.name < right.name
  end)

  return repos
end

local function sync_one(url, config)
  local name = repo_name(url)
  local path = config.sandbox_dir .. "/" .. name
  local result

  if util.is_dir(path .. "/.git") then
    result = vim.system({ "git", "-C", path, "fetch", "--all", "--prune" }, {
      text = true,
    }):wait()
    if result.code == 0 then
      return string.format("updated %s", name)
    end
    return string.format("failed %s: %s", name, util.trim(result.stderr))
  end

  result = vim.system({ "git", "clone", url, path }, {
    text = true,
  }):wait()
  if result.code == 0 then
    return string.format("cloned %s", name)
  end
  return string.format("failed %s: %s", name, util.trim(result.stderr))
end

function M.sync(config)
  util.ensure_dir(config.sandbox_dir)
  local messages = {}
  for _, url in ipairs(config.repositories) do
    table.insert(messages, sync_one(url, config))
  end
  return messages
end

return M
