local util = require("code_reviewer_helper.util")

local M = {}

local fallback_prompt = [[
BTCA Local instructions:
- Search local git repositories cloned under the BTCA sandbox directory when useful.
- Prefer the small set of repositories resolved as most important from the active workspace's dependency manifests.
- Prefer repository facts over guessing.
- Include citations to repository files and any web docs used.
- Keep explanations concrete and oriented around the selected code.
]]

local package_dependency_priorities = {
  dependencies = 500,
  peerDependencies = 450,
  optionalDependencies = 350,
  devDependencies = 100,
}

local manifest_parsers = {}
local source_priorities = {
  ["Cargo.toml git"] = 400,
  ["go.mod replace"] = 475,
  ["go.mod require"] = 425,
  ["pyproject.toml git"] = 300,
  ["requirements.txt git"] = 250,
  ["btca.repositories"] = 1000,
}

local function repo_name(url)
  return url:match("/([^/]+)%.git$") or url:match("/([^/#]+)")
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function unique_insert(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return
    end
  end
  table.insert(list, value)
end

local function normalize_http_url(host, path)
  path = path:gsub("[?#].*$", "")
  path = path:gsub("^/+", "")
  path = path:gsub("/+$", "")
  if path == "" then
    return nil
  end

  local segments = vim.split(path, "/", { plain = true, trimempty = true })
  if #segments < 2 then
    return nil
  end

  if host == "github.com" or host == "bitbucket.org" then
    path = segments[1] .. "/" .. segments[2]
  else
    for index, segment in ipairs(segments) do
      if segment == "-" or segment == "tree" or segment == "blob" then
        path = table.concat(vim.list_slice(segments, 1, index - 1), "/")
        break
      end
    end
  end

  path = path:gsub("%.git$", "")
  return string.format("https://%s/%s.git", host, path)
end

local function normalize_module_repo(path)
  local host, rest = path:match("^([%w%.%-]+)/(.*)$")
  if not host or not rest then
    return nil
  end
  if host ~= "github.com" and host ~= "gitlab.com" and host ~= "bitbucket.org" then
    return nil
  end

  local segments = vim.split(rest, "/", { plain = true, trimempty = true })
  if #segments < 2 then
    return nil
  end

  return string.format("https://%s/%s/%s.git", host, segments[1], segments[2])
end

local function normalize_repository_url(value)
  local url = util.trim(value)
  if url == "" then
    return nil
  end

  url = url:gsub("^git%+", "")
  url = url:gsub("[?#].*$", "")

  if url:match("^file://") then
    return url
  end

  local github_short = url:match("^github:([^#]+)$")
  if github_short then
    return "https://github.com/" .. github_short:gsub("%.git$", "") .. ".git"
  end

  local owner, repo = url:match("^([%w%._-]+)/([%w%._-]+)$")
  if owner and repo then
    return string.format("https://github.com/%s/%s.git", owner, repo:gsub("%.git$", ""))
  end

  local ssh_host, ssh_path = url:match("^git@([^:]+):(.+)$")
  if ssh_host and ssh_path then
    return normalize_http_url(ssh_host, ssh_path)
  end

  local host, path = url:match("^ssh://git@([^/]+)/(.+)$")
  if host and path then
    return normalize_http_url(host, path)
  end

  host, path = url:match("^https?://([^/]+)/(.+)$")
  if host and path then
    return normalize_http_url(host, path)
  end

  return nil
end

local function repository_label(url)
  if url:match("^file://") then
    return repo_name(url)
  end

  local host, path = url:match("^https?://([^/]+)/(.+)$")
  if host and path then
    return host .. "/" .. path:gsub("%.git$", "")
  end

  return repo_name(url)
end

local function repository_dir_name(url)
  return repository_label(url):gsub("[^%w%._-]+", "__")
end

local function repository_path(config, url)
  local preferred = config.sandbox_dir .. "/" .. repository_dir_name(url)
  if util.is_dir(preferred .. "/.git") then
    return preferred
  end

  local legacy = config.sandbox_dir .. "/" .. repo_name(url)
  if util.is_dir(legacy .. "/.git") then
    return legacy
  end

  return preferred
end

local function add_repository(map, url, source, priority)
  local normalized = normalize_repository_url(url)
  if not normalized then
    return
  end

  local entry = map[normalized]
  if not entry then
    entry = {
      url = normalized,
      name = repository_label(normalized),
      sources = {},
      priority = 0,
    }
    map[normalized] = entry
  end

  if source and source ~= "" then
    unique_insert(entry.sources, source)
  end
  entry.priority = math.max(entry.priority or 0, priority or 0)
end

local function parse_package_json(content, source, map)
  local data = util.json_decode(content, {})
  if type(data) ~= "table" then
    return
  end

  for key, priority in pairs(package_dependency_priorities) do
    local dependencies = data[key]
    if type(dependencies) == "table" then
      for _, spec in pairs(dependencies) do
        if type(spec) == "string" then
          add_repository(map, spec, source .. " " .. key, priority)
        end
      end
    end
  end
end

local function parse_cargo_toml(content, source, map)
  for url in content:gmatch('git%s*=%s*"([^"]+)"') do
    add_repository(map, url, source .. " git", source_priorities["Cargo.toml git"])
  end
  for url in content:gmatch("git%s*=%s*'([^']+)'") do
    add_repository(map, url, source .. " git", source_priorities["Cargo.toml git"])
  end
end

local function parse_go_mod(content, source, map)
  local mode = nil

  for raw_line in content:gmatch("[^\r\n]+") do
    local line = util.trim(raw_line:gsub("//.*$", ""))
    if line == "" then
      goto continue
    end

    if line:match("^require%s*%($") then
      mode = "require"
      goto continue
    end
    if line:match("^replace%s*%($") then
      mode = "replace"
      goto continue
    end
    if line == ")" then
      mode = nil
      goto continue
    end

    local module_path = nil
    local line_mode = mode
    if mode == "require" then
      module_path = line:match("^([^%s]+)%s+[^%s]+$")
    elseif mode == "replace" then
      module_path = line:match("=>%s*([^%s]+)")
    elseif line:match("^require%s+") then
      module_path = line:match("^require%s+([^%s]+)%s+[^%s]+$")
      line_mode = "require"
    elseif line:match("^replace%s+") then
      module_path = line:match("=>%s*([^%s]+)")
      line_mode = "replace"
    end

    if module_path then
      local url = normalize_module_repo(module_path)
      if url then
        local source_label = line_mode == "replace" and (source .. " replace")
          or (source .. " require")
        local priority = line_mode == "replace" and source_priorities["go.mod replace"]
          or source_priorities["go.mod require"]
        add_repository(map, url, source_label, priority)
      end
    end

    ::continue::
  end
end

local function scan_git_urls(content, source, map)
  for raw in content:gmatch("git%+[^%s\"',%)%]]+") do
    add_repository(map, raw, source, source_priorities[source] or 0)
  end
end

local function parse_requirements(content, source, map)
  scan_git_urls(content, source .. " git", map)
end

local function parse_pyproject(content, source, map)
  scan_git_urls(content, source .. " git", map)
  for url in content:gmatch('git%s*=%s*"([^"]+)"') do
    add_repository(map, url, source .. " git", source_priorities["pyproject.toml git"])
  end
  for url in content:gmatch("git%s*=%s*'([^']+)'") do
    add_repository(map, url, source .. " git", source_priorities["pyproject.toml git"])
  end
end

manifest_parsers["package.json"] = parse_package_json
manifest_parsers["Cargo.toml"] = parse_cargo_toml
manifest_parsers["go.mod"] = parse_go_mod
manifest_parsers["requirements.txt"] = parse_requirements
manifest_parsers["pyproject.toml"] = parse_pyproject

local function discover_workspace_repositories(workspace_root)
  local discovered = {}

  if not workspace_root or not util.is_dir(workspace_root) then
    return discovered
  end

  for _, relative_path in ipairs(util.list_files(workspace_root)) do
    local parser = manifest_parsers[basename(relative_path)]
    if parser then
      local full_path = workspace_root .. "/" .. relative_path
      local content = util.read_file(full_path, 262144)
      if content and content ~= "" then
        parser(content, relative_path, discovered)
      end
    end
  end

  return discovered
end

local function map_to_list(config, repos)
  local list = {}

  for _, repo in pairs(repos) do
    repo.path = repository_path(config, repo.url)
    repo.available = util.is_dir(repo.path .. "/.git")
    table.sort(repo.sources)
    table.insert(list, repo)
  end

  table.sort(list, function(left, right)
    if (left.priority or 0) ~= (right.priority or 0) then
      return (left.priority or 0) > (right.priority or 0)
    end
    if left.available ~= right.available then
      return left.available and not right.available
    end
    return left.name < right.name
  end)

  local max_repositories = math.max(0, math.floor(config.max_repositories or 0))
  if max_repositories > 0 and #list > max_repositories then
    while #list > max_repositories do
      table.remove(list)
    end
  end

  return list
end

local function sync_one(repo)
  local result

  if util.is_dir(repo.path .. "/.git") then
    result = vim.system({ "git", "-C", repo.path, "fetch", "--all", "--prune" }, {
      text = true,
    }):wait()
    if result.code == 0 then
      return string.format("updated %s", repo.name)
    end
    return string.format("failed %s: %s", repo.name, util.trim(result.stderr))
  end

  result = vim.system({ "git", "clone", repo.url, repo.path }, {
    text = true,
  }):wait()
  if result.code == 0 then
    return string.format("cloned %s", repo.name)
  end
  return string.format("failed %s: %s", repo.name, util.trim(result.stderr))
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

function M.ensure_skill(config)
  local data = util.read_file(config.skill_path)
  if data and data ~= "" then
    return true
  end
  if not config.fallback_prompt then
    return false
  end

  local ok = pcall(util.write_file, config.skill_path, fallback_prompt)
  if not ok then
    return false
  end

  data = util.read_file(config.skill_path)
  return data ~= nil and data ~= ""
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

function M.resolve_repositories(config, workspace_root)
  local repositories = discover_workspace_repositories(workspace_root)

  for _, url in ipairs(config.repositories or {}) do
    add_repository(
      repositories,
      url,
      "btca.repositories",
      source_priorities["btca.repositories"]
    )
  end

  return map_to_list(config, repositories)
end

function M.sync(config, workspace_root)
  util.ensure_dir(config.sandbox_dir)
  local repos = M.resolve_repositories(config, workspace_root)
  if #repos == 0 then
    return { "no BTCA dependency repositories discovered for this workspace" }
  end

  local messages = {}
  for _, repo in ipairs(repos) do
    table.insert(messages, sync_one(repo))
  end
  return messages
end

return M
