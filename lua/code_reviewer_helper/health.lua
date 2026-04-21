local btca = require("code_reviewer_helper.btca")
local provider = require("code_reviewer_helper.provider.codex_exec")
local util = require("code_reviewer_helper.util")

local M = {}

local function add_report(lines, status, text)
  table.insert(lines, string.format("[%s] %s", status, text))
end

function M.run(config)
  local lines = { "Code Review Helper health" }

  if provider.is_available(config) then
    add_report(lines, "OK", "codex binary is executable")
  else
    add_report(lines, "ERROR", "codex binary is not executable: " .. config.codex.bin)
  end

  if util.command_exists("git") then
    add_report(lines, "OK", "git is executable")
  else
    add_report(lines, "ERROR", "git is not executable")
  end

  if btca.ensure_skill(config.btca) then
    add_report(lines, "OK", "BTCA skill file is present")
  elseif config.btca.fallback_prompt then
    add_report(lines, "WARN", "BTCA skill file is missing and could not be installed; embedded BTCA prompt will be used")
  else
    add_report(lines, "ERROR", "BTCA skill file is missing and fallback is disabled")
  end

  if util.ensure_dir(config.btca.sandbox_dir) then
    add_report(lines, "OK", "BTCA sandbox directory is available")
  else
    add_report(lines, "ERROR", "BTCA sandbox directory is not writable")
  end

  local buffer_path = vim.api.nvim_buf_get_name(0)
  local workspace_root = buffer_path ~= "" and util.git_root(buffer_path) or nil
  if workspace_root then
    add_report(lines, "OK", "workspace root resolved: " .. workspace_root)
  else
    add_report(lines, "WARN", "workspace root could not be resolved from the current buffer")
  end

  if util.mode_is_visual() then
    add_report(lines, "OK", "visual mode is active")
  else
    add_report(lines, "WARN", "visual mode is not active")
  end

  local repo_count = #btca.list_repositories(config.btca)
  add_report(lines, "OK", string.format("BTCA sandbox currently contains %d repositories", repo_count))

  if workspace_root then
    local workspace_repos = btca.resolve_repositories(config.btca, workspace_root)
    local available_count = 0
    for _, repo in ipairs(workspace_repos) do
      if repo.available then
        available_count = available_count + 1
      end
    end
    add_report(
      lines,
        "OK",
        string.format(
        "current workspace resolves %d prioritized BTCA dependency repositories (%d available locally)",
        #workspace_repos,
        available_count
      )
    )
  end

  add_report(lines, "WARN", "authentication is not probed live; run :CRHExplain to verify Codex session auth")

  util.notify(table.concat(lines, "\n"))
  return lines
end

return M
