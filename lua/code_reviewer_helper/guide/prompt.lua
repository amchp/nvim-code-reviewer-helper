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

function M.build(context, config)
  local lines = {
    "You are planning the fastest way for a Neovim user to understand this codebase.",
    "Return exactly two sections in this order and nothing else.",
    "First: a fenced json block.",
    "Second: a markdown document headed '# Review Order'.",
    "The JSON must be valid and must include mode, summary, and items.",
    "Each item must include path, reason, status, and old_path.",
    "Statuses must be one of modified, added, deleted, renamed, untracked, repo.",
    "Keep reasons short and concrete.",
    string.format("In repo mode, return at most %d items.", config.guide.repo_mode_max_files),
    "",
  }

  add_section(lines, "Expected JSON Shape", {
    "```json",
    [[{"mode":"changes|repo","summary":"short string","items":[{"path":"relative/path","reason":"short rationale","status":"modified|added|deleted|renamed|untracked|repo","old_path":null}]}]],
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

  if context.mode == "changes" and context.changes then
    add_section(lines, "Git Status", context.changes.status_lines)
    add_section(lines, "Diff Stat", context.changes.diff_stat ~= "" and context.changes.diff_stat or "(empty)")
    add_section(lines, "Changed File Excerpts", render_changes(context.changes.items))
  else
    add_section(lines, "Task", "Choose the best first-pass order to understand this repository quickly.")
  end

  add_section(lines, "Markdown Requirements", {
    "- Start with '# Review Order'.",
    "- Include the overall summary.",
    "- Include the ordered file list with one short reason per file.",
  })

  return table.concat(lines, "\n")
end

return M
