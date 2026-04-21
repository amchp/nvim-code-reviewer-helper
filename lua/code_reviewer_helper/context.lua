local btca = require("code_reviewer_helper.btca")
local util = require("code_reviewer_helper.util")

local M = {}

local function find_docs(root, path, names, max_bytes)
  local docs = {}
  local current = vim.fn.fnamemodify(path, ":p:h")

  while current and current ~= "" do
    for _, name in ipairs(names) do
      local doc_path = current .. "/" .. name
      if util.file_exists(doc_path) then
        table.insert(docs, {
          path = doc_path,
          relative_path = util.relative_path(root or current, doc_path),
          content = util.read_file(doc_path, max_bytes) or "",
        })
      end
    end

    if root and current == root then
      break
    end

    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end

  return docs
end

function M.build(selection, config, workspace_root)
  local root = workspace_root or util.git_root(selection.path) or vim.uv.cwd()
  local docs = find_docs(
    root,
    selection.path,
    config.context.md_files,
    config.context.max_doc_bytes
  )
  local btca_skill = nil
  local btca_repos = {}

  if config.btca.enabled then
    btca_skill = btca.skill_content(config.btca)
    btca_repos = btca.resolve_repositories(config.btca, root)
  end

  return {
    workspace_root = root,
    docs = docs,
    btca_skill = btca_skill,
    btca_repos = btca_repos,
  }
end

return M
