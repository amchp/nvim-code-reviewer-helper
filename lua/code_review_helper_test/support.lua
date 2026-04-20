local M = {}

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(message or string.format(
      "expected %s but got %s",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

function M.ok(value, message)
  if not value then
    error(message or "expected truthy value")
  end
end

function M.match(pattern, value, message)
  if not tostring(value):match(pattern) then
    error(message or string.format("expected %q to match %q", tostring(value), pattern))
  end
end

function M.tmp_dir(name)
  local path = vim.fn.tempname() .. "_" .. name
  vim.fn.mkdir(path, "p")
  return path
end

function M.write(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, content, 0))
  assert(vim.uv.fs_close(fd))
end

function M.read(path)
  local fd = vim.uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

function M.new_buffer(lines, name)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, name or (vim.fn.tempname() .. ".lua"))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

function M.set_visual_marks(buf, start_row, start_col, end_row, end_col)
  vim.api.nvim_buf_set_mark(buf, "<", start_row, math.max(start_col - 1, 0), {})
  vim.api.nvim_buf_set_mark(buf, ">", end_row, math.max(end_col - 1, 0), {})
end

function M.wait(ms)
  vim.wait(ms or 3000, function()
    return false
  end)
end

function M.reset_package(name)
  package.loaded[name] = nil
end

function M.load_helper()
  local prefix = "code_reviewer_helper"
  for name in pairs(package.loaded) do
    if name == prefix or vim.startswith(name, prefix .. ".") then
      package.loaded[name] = nil
    end
  end
  return require("code_reviewer_helper")
end

return M
