local util = require("code_reviewer_helper.util")

local M = {}

local function relative_doc(root, name, max_bytes)
  local path = root .. "/" .. name
  if not util.file_exists(path) then
    return nil
  end

  return {
    path = path,
    relative_path = name,
    content = util.read_file(path, max_bytes) or "",
  }
end

local function read_docs(root, names, max_bytes)
  local docs = {}
  for _, name in ipairs(names or {}) do
    local doc = relative_doc(root, name, max_bytes)
    if doc then
      table.insert(docs, doc)
    end
  end
  return docs
end

local function classify_file(path)
  if path == "README.md" or path == "AGENTS.md" then
    return "docs"
  end
  if path:match("^plugin/") then
    return "entrypoint"
  end
  if path:match("/init%.lua$") or path:match("^lua/.+init%.lua$") then
    return "module"
  end
  if path:match("^tests?/") then
    return "tests"
  end
  if path:match("%.md$") then
    return "docs"
  end
  if path:match("^lua/") then
    return "source"
  end
  return "other"
end

local function build_inventory(root)
  local files = util.list_files(root)
  local items = {}
  local set = {}
  for _, path in ipairs(files) do
    set[path] = true
    table.insert(items, {
      path = path,
      kind = classify_file(path),
    })
  end
  return items, set
end

local function parse_status_line(line)
  local xy = line:sub(1, 2)
  local payload = line:sub(4)
  if xy == "??" then
    return {
      path = payload,
      status = "untracked",
      git_status = "?",
    }
  end

  local old_path, new_path = payload:match("^(.-) %-%> (.+)$")
  if old_path and new_path then
    return {
      path = new_path,
      old_path = old_path,
      status = "renamed",
      git_status = "R",
    }
  end

  if xy:find("D", 1, true) then
    return {
      path = payload,
      status = "deleted",
      git_status = "D",
    }
  end

  if xy:find("A", 1, true) then
    return {
      path = payload,
      status = "added",
      git_status = "A",
    }
  end

  if xy:find("R", 1, true) then
    return {
      path = payload,
      status = "renamed",
      git_status = "R",
    }
  end

  return {
    path = payload,
    status = "modified",
    git_status = "M",
  }
end

local function diff_excerpt(root, item, max_bytes)
  if item.status == "untracked" then
    return util.read_file(root .. "/" .. item.path, max_bytes) or ""
  end

  local command = { "git", "-C", root, "diff", "--no-ext-diff", "--unified=3", "HEAD", "--" }
  if item.old_path then
    table.insert(command, item.old_path)
  end
  if item.path ~= item.old_path then
    table.insert(command, item.path)
  end

  local result = util.system(command)
  return result.stdout:sub(1, max_bytes)
end

local function diff_stats(root, item)
  local command = { "git", "-C", root, "diff", "--numstat", "HEAD", "--" }
  if item.old_path then
    table.insert(command, item.old_path)
  end
  if item.path ~= item.old_path then
    table.insert(command, item.path)
  end
  local result = util.system(command)
  local line = vim.split(util.trim(result.stdout), "\n", { plain = true })[1] or ""
  local additions, deletions = line:match("^(%d+)%s+(%d+)")
  if additions and deletions then
    return {
      additions = tonumber(additions),
      deletions = tonumber(deletions),
    }
  end
  return nil
end

local function collect_changes(root, config)
  local command = {
    "git",
    "-C",
    root,
    "status",
    "--porcelain=v1",
    config.include_untracked and "--untracked-files=all" or "--untracked-files=no",
  }
  local status_result = util.system(command)
  local lines = vim.split(util.trim(status_result.stdout), "\n", { plain = true })
  local items = {}

  for _, line in ipairs(lines) do
    if line ~= "" then
      local item = parse_status_line(line)
      item.diff_excerpt = diff_excerpt(root, item, config.max_diff_bytes_per_file)
      item.stats = diff_stats(root, item)
      table.insert(items, item)
    end
  end

  local diff_stat = util.system({ "git", "-C", root, "diff", "--stat", "HEAD", "--" }).stdout
  return {
    status_lines = lines,
    diff_stat = diff_stat,
    items = items,
  }
end

function M.build(start_path, config)
  local workspace_root = util.git_root(start_path) or start_path
  local git_root = util.git_root(start_path)
  local docs = read_docs(workspace_root, config.context.md_files, config.guide.max_doc_bytes)
  local inventory, valid_paths = build_inventory(workspace_root)
  local changes = nil
  local mode = "repo"

  if git_root then
    changes = collect_changes(git_root, config.guide)
    if #changes.items > 0 then
      mode = "changes"
    end
  end

  return {
    workspace_root = workspace_root,
    git_root = git_root,
    docs = docs,
    inventory = inventory,
    valid_paths = valid_paths,
    changes = changes,
    mode = mode,
  }
end

return M
