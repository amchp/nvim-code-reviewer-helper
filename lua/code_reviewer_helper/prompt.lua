local util = require("code_reviewer_helper.util")

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

function M.build(question, selection, context)
  local lines = {
    "You are helping a Neovim user understand a selected piece of code.",
    "The task is explain-only. Do not propose edits unless the user explicitly asks.",
    "Give a short explanation, not a deep review or long walkthrough, unless the user explicitly asks for depth.",
    "Prefer repository evidence first. Use web documentation only when local context is insufficient.",
    "Cite the specific local files and web docs you actually used.",
    "",
  }

  add_section(lines, "User Question", question)
  add_section(lines, "File", {
    "- Path: " .. selection.path,
    "- Filetype: " .. selection.filetype,
    "- Workspace root: " .. context.workspace_root,
    string.format(
      "- Range: %d:%d to %d:%d",
      selection.range.start_row,
      selection.range.start_col,
      selection.range.end_row,
      selection.range.end_col
    ),
  })

  if selection.symbol then
    add_section(lines, "Nearest Symbol", selection.symbol)
  end

  add_section(lines, "Selected Code", {
    "```" .. selection.filetype,
    util.normalize_lines(selection.selected_lines),
    "```",
  })

  if #selection.surrounding_lines.before > 0 then
    add_section(lines, "Code Before Selection", {
      "```" .. selection.filetype,
      util.normalize_lines(selection.surrounding_lines.before),
      "```",
    })
  end

  if #selection.surrounding_lines.after > 0 then
    add_section(lines, "Code After Selection", {
      "```" .. selection.filetype,
      util.normalize_lines(selection.surrounding_lines.after),
      "```",
    })
  end

  if selection.diagnostics and #selection.diagnostics > 0 then
    local diagnostic_lines = {}
    for _, item in ipairs(selection.diagnostics) do
      table.insert(
        diagnostic_lines,
        string.format(
          "- %s at %d:%d: %s",
          item.severity,
          item.row,
          item.col,
          item.message
        )
      )
    end
    add_section(lines, "Diagnostics", diagnostic_lines)
  end

  if context.docs and #context.docs > 0 then
    local doc_lines = {}
    for _, doc in ipairs(context.docs) do
      table.insert(doc_lines, "### " .. doc.relative_path)
      table.insert(doc_lines, "```markdown")
      table.insert(doc_lines, doc.content)
      table.insert(doc_lines, "```")
      table.insert(doc_lines, "")
    end
    add_section(lines, "Project Docs", doc_lines)
  end

  if context.btca_skill then
    add_section(lines, "BTCA Instructions", context.btca_skill)
  end

  if context.btca_repos and #context.btca_repos > 0 then
    local repo_lines = {}
    for _, repo in ipairs(context.btca_repos) do
      local sources = repo.sources and table.concat(repo.sources, ", ") or "unknown"
      if repo.available then
        table.insert(
          repo_lines,
          string.format("- available %s at %s (from %s)", repo.name, repo.path, sources)
        )
      else
        table.insert(
          repo_lines,
          string.format("- not synced %s from %s", repo.name, sources)
        )
      end
    end
    add_section(lines, "BTCA Dependency Repositories", repo_lines)
  end

  add_section(lines, "Response Requirements", {
    "- Keep the explanation to 2 short paragraphs or up to 4 flat bullets.",
    "- Prefer under 120 words before the Sources section.",
    "- Cover only the main purpose and the most important behavior.",
    "- Mention one caveat only if it materially affects understanding.",
    "- Do not explain every line.",
    "- End with a Sources section.",
    "- Sources should contain 1 to 3 bullets.",
    "- Prefer local file citations first.",
    "- Include web citations only if web docs were actually used.",
  })

  return table.concat(lines, "\n")
end

return M
