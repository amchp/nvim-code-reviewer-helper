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

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function is_review_noise(path)
  local name = basename(path)
  return name == ".DS_Store"
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

local function parse_name_status_line(line)
  local parts = vim.split(line, "\t", { plain = true })
  local status_code = parts[1] or ""
  local code = status_code:sub(1, 1)
  if code == "R" then
    return {
      path = parts[3],
      old_path = parts[2],
      status = "renamed",
      git_status = "R",
    }
  end
  if code == "A" then
    return { path = parts[2], status = "added", git_status = "A" }
  end
  if code == "D" then
    return { path = parts[2], status = "deleted", git_status = "D" }
  end
  if code == "M" then
    return { path = parts[2], status = "modified", git_status = "M" }
  end
  return nil
end

local function diff_excerpt(root, item, max_bytes, base_rev)
  if item.status == "untracked" then
    return util.read_file(root .. "/" .. item.path, max_bytes) or ""
  end

  local command = { "git", "-C", root, "diff", "--no-ext-diff", "--unified=3", base_rev or "HEAD", "--" }
  if item.old_path then
    table.insert(command, item.old_path)
  end
  if item.path ~= item.old_path then
    table.insert(command, item.path)
  end

  local result = util.system(command)
  return result.stdout:sub(1, max_bytes)
end

local function diff_stats(root, item, base_rev)
  local command = { "git", "-C", root, "diff", "--numstat", base_rev or "HEAD", "--" }
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

local function collect_worktree_changes(root, config)
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
      if not is_review_noise(item.path) then
        item.diff_excerpt = diff_excerpt(root, item, config.max_diff_bytes_per_file)
        item.stats = diff_stats(root, item)
        table.insert(items, item)
      end
    end
  end

  local diff_stat = util.system({ "git", "-C", root, "diff", "--stat", "HEAD", "--" }).stdout
  return {
    status_lines = lines,
    diff_stat = diff_stat,
    items = items,
  }
end

local function collect_untracked(root, config, seen)
  if not config.include_untracked then
    return {}
  end
  local result = util.system({
    "git",
    "-C",
    root,
    "ls-files",
    "--others",
    "--exclude-standard",
  })
  local items = {}
  for _, path in ipairs(vim.split(util.trim(result.stdout or ""), "\n", { plain = true })) do
    if path ~= "" and not seen[path] and not is_review_noise(path) then
      seen[path] = true
      table.insert(items, {
        path = path,
        status = "untracked",
        git_status = "?",
        diff_excerpt = util.read_file(root .. "/" .. path, config.max_diff_bytes_per_file) or "",
      })
    end
  end
  return items
end

local function collect_aggregate_changes(root, config, commit_count)
  local base_rev = "HEAD~" .. tostring(commit_count)
  local name_status = util.system({
    "git",
    "-C",
    root,
    "diff",
    "--name-status",
    base_rev,
  })
  if name_status.code ~= 0 then
    return nil, "Unable to diff against " .. base_rev
  end

  local items = {}
  local seen = {}
  for _, line in ipairs(vim.split(util.trim(name_status.stdout or ""), "\n", { plain = true })) do
    if line ~= "" then
      local item = parse_name_status_line(line)
      if item and item.path and not seen[item.path] and not is_review_noise(item.path) then
        seen[item.path] = true
        item.diff_excerpt = diff_excerpt(root, item, config.max_diff_bytes_per_file, base_rev)
        item.stats = diff_stats(root, item, base_rev)
        table.insert(items, item)
      end
    end
  end

  for _, item in ipairs(collect_untracked(root, config, seen)) do
    table.insert(items, item)
  end

  local diff_stat = util.system({ "git", "-C", root, "diff", "--stat", base_rev }).stdout
  local uncommitted = util.system({ "git", "-C", root, "diff", "--quiet", "HEAD" }).code ~= 0
  return {
    base_rev = base_rev,
    commit_count = commit_count,
    uncommitted_included = uncommitted or #collect_untracked(root, config, {}) > 0,
    status_lines = vim.split(util.trim(name_status.stdout or ""), "\n", { plain = true }),
    diff_stat = diff_stat,
    items = items,
  }
end

function M.previous_commits(git_root, count)
  if not git_root then
    return {}
  end
  local result = util.system({
    "git",
    "-C",
    git_root,
    "log",
    "-" .. tostring(count or 5),
    "--pretty=format:%h %s",
  })
  if result.code ~= 0 then
    return {}
  end
  local commits = {}
  for _, line in ipairs(vim.split(util.trim(result.stdout or ""), "\n", { plain = true })) do
    if line ~= "" then
      table.insert(commits, line)
    end
  end
  return commits
end

function M.build(start_path, config, opts)
  opts = opts or {}
  local workspace_root = util.git_root(start_path) or start_path
  local git_root = util.git_root(start_path)
  local docs = read_docs(workspace_root, config.context.md_files, config.guide.max_doc_bytes)
  local inventory, valid_paths = build_inventory(workspace_root)
  local changes = nil
  local mode = opts.mode or "codebase"
  local err = nil

  if mode == "git_changes" then
    if not git_root then
      err = "Git Changes Review requires a git repository"
    else
      changes, err = collect_aggregate_changes(git_root, config.guide, opts.commit_count)
    end
  elseif git_root then
    changes = collect_worktree_changes(git_root, config.guide)
  end

  return {
    workspace_root = workspace_root,
    git_root = git_root,
    docs = docs,
    inventory = inventory,
    valid_paths = valid_paths,
    changes = changes,
    mode = mode,
    error = err,
    selected_commits = opts.selected_commits,
  }
end

return M
