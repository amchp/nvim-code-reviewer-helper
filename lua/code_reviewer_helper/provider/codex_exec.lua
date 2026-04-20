local util = require("code_reviewer_helper.util")

local M = {}

function M.is_available(config)
  return util.command_exists(config.codex.bin)
end

function M.build_command(request, config, output_path)
  local command = {
    config.codex.bin,
  }

  if config.codex.use_web_search then
    table.insert(command, "--search")
  end

  table.insert(command, "exec")
  table.insert(command, "-C")
  table.insert(command, request.workspace_root)
  table.insert(command, "--output-last-message")
  table.insert(command, output_path)
  table.insert(command, "--sandbox")
  table.insert(command, config.codex.sandbox)

  if config.btca.enabled then
    table.insert(command, "--add-dir")
    table.insert(command, config.btca.sandbox_dir)
  end

  if config.codex.model then
    table.insert(command, "--model")
    table.insert(command, config.codex.model)
  end

  for _, arg in ipairs(config.codex.extra_args or {}) do
    table.insert(command, arg)
  end

  table.insert(command, "-")
  return command
end

function M.submit(request, config, callbacks)
  local output_path = vim.fn.tempname() .. "_crh_response.md"
  local command = M.build_command(request, config, output_path)

  local proc = vim.system(command, {
    text = true,
    stdin = request.prompt,
  }, function(result)
    vim.schedule(function()
      callbacks.on_complete({
        code = result.code,
        stdout = result.stdout or "",
        stderr = result.stderr or "",
        output_path = output_path,
      })
    end)
  end)

  return {
    proc = proc,
    output_path = output_path,
    command = command,
  }
end

function M.cancel(job)
  if job and job.proc then
    pcall(job.proc.kill, job.proc, 15)
  end
end

return M
