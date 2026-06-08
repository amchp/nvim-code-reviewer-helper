local M = {}

local function add_section(lines, title, content)
  table.insert(lines, "## " .. title)
  table.insert(lines, "")
  if type(content) == "table" then
    for _, line in ipairs(content) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, content)
  end
  table.insert(lines, "")
end

local function render_docs(docs)
  local lines = {}
  for _, doc in ipairs(docs or {}) do
    table.insert(lines, "### " .. doc.relative_path)
    table.insert(lines, "```markdown")
    table.insert(lines, doc.content)
    table.insert(lines, "```")
    table.insert(lines, "")
  end
  return lines
end

local function render_inventory(items, max_files)
  local lines = {}
  for index, item in ipairs(items or {}) do
    if index > max_files then
      break
    end
    table.insert(lines, string.format("- %s [%s]", item.path, item.kind))
  end
  return lines
end

local function render_changes(items)
  local lines = {}
  for _, item in ipairs(items or {}) do
    table.insert(lines, string.format("### %s [%s]", item.path, item.status))
    if item.old_path then
      table.insert(lines, "- Old path: " .. item.old_path)
    end
    if item.stats then
      table.insert(lines, string.format("- Stats: +%d -%d", item.stats.additions, item.stats.deletions))
    end
    table.insert(lines, "```diff")
    table.insert(lines, item.diff_excerpt or "")
    table.insert(lines, "```")
    table.insert(lines, "")
  end
  return lines
end

local function render_commits(commits)
  local lines = {}
  for _, commit in ipairs(commits or {}) do
    if type(commit) == "table" then
      table.insert(lines, string.format("- %s %s", commit.short or "", commit.subject or ""))
    else
      table.insert(lines, "- " .. tostring(commit))
    end
  end
  if #lines == 0 then
    table.insert(lines, "(not available)")
  end
  return lines
end

function M.build(context, config)
  local title = context.mode == "git_changes" and "Git Changes Review" or "Codebase Review"
  local lines = {
    "You are planning a " .. title .. " for a Neovim user.",
    "Return exactly two sections in this order and nothing else.",
    "First: a fenced json block.",
    "Second: a markdown document headed '# Review Overview'.",
    "The JSON must be valid and must include mode, summary, overview_markdown, and items.",
    "Each item must include path, reason, status, and old_path.",
    "Statuses must be one of modified, added, deleted, renamed, untracked, repo.",
    "Mode must be exactly '" .. context.mode .. "'.",
    "Keep reasons short and concrete.",
    "Every item path must exactly match a path already listed in 'Repository Inventory' or 'Changed File Excerpts'.",
    "Do not invent, infer, or normalize paths. If a path is not listed, do not return it.",
    string.format("In codebase mode, return at most %d items.", config.guide.repo_mode_max_files),
    "",
  }

  add_section(lines, "Expected JSON Shape", {
    "```json",
    [[{"mode":"codebase|git_changes","summary":"short string","overview_markdown":"markdown body","items":[{"path":"relative/path","reason":"short rationale","status":"repo|modified|added|deleted|renamed|untracked","old_path":null}]}]],
    "```",
  })

  add_section(lines, "Workspace", {
    "- Root: " .. context.workspace_root,
    "- Mode: " .. context.mode,
  })

  if context.docs and #context.docs > 0 then
    add_section(lines, "Project Docs", render_docs(context.docs))
  end

  add_section(lines, "Repository Inventory", render_inventory(context.inventory, 200))

  if context.mode == "git_changes" and context.changes then
    add_section(lines, "Git Changes Review Scope", {
      "- Base: " .. context.changes.base_rev,
      "- Right side: current working tree",
      "- Selected commit count: " .. tostring(context.changes.commit_count),
      "- Uncommitted changes included: " .. tostring(context.changes.uncommitted_included == true),
      "- Include committed changes, uncommitted tracked changes, and configured untracked files.",
      "- Treat this as one aggregate GitHub-style review, not separate per-commit sections.",
    })
    add_section(lines, "Selected Commits Newest First", render_commits(context.selected_commits))
    add_section(lines, "Git Status", context.changes.status_lines)
    add_section(lines, "Diff Stat", context.changes.diff_stat ~= "" and context.changes.diff_stat or "(empty)")
    add_section(lines, "Changed File Excerpts", render_changes(context.changes.items))
  else
    add_section(lines, "Task", {
      "Describe the general codebase structure in overview_markdown.",
      "Choose the best first-pass order to understand this repository quickly.",
    })
  end

  add_section(lines, "Markdown Requirements", {
    "- Start with '# Review Overview'.",
    "- Include the overall summary.",
    "- Describe the general structure or aggregate change shape.",
    "- Include the ordered file list with one short reason per file.",
  })

  return table.concat(lines, "\n")
end

function M.build_repair(context, config, response, err)
  local lines = {
    M.build(context, config),
    "## Previous Attempt Failed",
    "",
    "- Parser error: " .. err,
    "- Fix the previous response so it matches the required format and only uses valid repository paths.",
    "- Return exactly the same two sections as before and nothing else.",
    "",
    "## Previous Response",
    "",
    "<previous_response>",
    response or "",
    "</previous_response>",
    "",
  }

  return table.concat(lines, "\n")
end

return M
