local M = {}

function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, {
      title = "code-reviewer-helper",
    })
  end)
end

function M.file_exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil
end

function M.is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

function M.ensure_dir(path)
  local result = vim.fn.mkdir(path, "p")
  return result == 1 or result == 2
end

function M.read_file(path, max_bytes)
  local fd = vim.uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end

  local stat = vim.uv.fs_fstat(fd)
  local size = stat and stat.size or 0
  local read_size = max_bytes and math.min(size, max_bytes) or size
  local data = vim.uv.fs_read(fd, read_size, 0)
  vim.uv.fs_close(fd)
  return data
end

local function is_continuation_byte(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

function M.ensure_utf8(value, replacement)
  if type(value) ~= "string" then
    return value
  end
  if value == "" then
    return value
  end
  if pcall(vim.str_utfindex, value) then
    return value
  end

  replacement = replacement or "?"

  local out = {}
  local index = 1
  local length = #value

  while index <= length do
    local byte1 = value:byte(index)

    if byte1 < 0x80 then
      out[#out + 1] = string.char(byte1)
      index = index + 1
    elseif byte1 >= 0xC2 and byte1 <= 0xDF then
      local byte2 = value:byte(index + 1)
      if is_continuation_byte(byte2) then
        out[#out + 1] = value:sub(index, index + 1)
        index = index + 2
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif byte1 == 0xE0 then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      if byte2 and byte2 >= 0xA0 and byte2 <= 0xBF and is_continuation_byte(byte3) then
        out[#out + 1] = value:sub(index, index + 2)
        index = index + 3
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif (byte1 >= 0xE1 and byte1 <= 0xEC) or (byte1 >= 0xEE and byte1 <= 0xEF) then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      if is_continuation_byte(byte2) and is_continuation_byte(byte3) then
        out[#out + 1] = value:sub(index, index + 2)
        index = index + 3
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif byte1 == 0xED then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      if byte2 and byte2 >= 0x80 and byte2 <= 0x9F and is_continuation_byte(byte3) then
        out[#out + 1] = value:sub(index, index + 2)
        index = index + 3
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif byte1 == 0xF0 then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      local byte4 = value:byte(index + 3)
      if byte2 and byte2 >= 0x90 and byte2 <= 0xBF and is_continuation_byte(byte3) and is_continuation_byte(byte4) then
        out[#out + 1] = value:sub(index, index + 3)
        index = index + 4
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif byte1 >= 0xF1 and byte1 <= 0xF3 then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      local byte4 = value:byte(index + 3)
      if is_continuation_byte(byte2) and is_continuation_byte(byte3) and is_continuation_byte(byte4) then
        out[#out + 1] = value:sub(index, index + 3)
        index = index + 4
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    elseif byte1 == 0xF4 then
      local byte2 = value:byte(index + 1)
      local byte3 = value:byte(index + 2)
      local byte4 = value:byte(index + 3)
      if byte2 and byte2 >= 0x80 and byte2 <= 0x8F and is_continuation_byte(byte3) and is_continuation_byte(byte4) then
        out[#out + 1] = value:sub(index, index + 3)
        index = index + 4
      else
        out[#out + 1] = replacement
        index = index + 1
      end
    else
      out[#out + 1] = replacement
      index = index + 1
    end
  end

  return table.concat(out)
end

function M.read_lines(path, max_bytes)
  local data = M.read_file(path, max_bytes)
  if not data then
    return nil
  end
  return vim.split(data, "\n", { plain = true })
end

function M.write_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  M.ensure_dir(dir)
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, content, 0))
  assert(vim.uv.fs_close(fd))
end

function M.json_decode(data, default)
  if not data or data == "" then
    return default
  end
  local ok, decoded = pcall(vim.json.decode, data)
  if not ok then
    return default
  end
  return decoded
end

function M.json_encode(data)
  return vim.json.encode(data)
end

function M.workspace_id(path)
  return vim.fn.sha256(path)
end

function M.normalize_lines(lines)
  return table.concat(lines, "\n")
end

function M.trim(value)
  return vim.trim(value or "")
end

function M.command_exists(bin)
  return vim.fn.executable(bin) == 1
end

function M.git_root(path)
  local dir = path
  if dir == "" then
    dir = vim.uv.cwd()
  end
  if not M.is_dir(dir) then
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  local result = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, {
    text = true,
  }):wait()
  if result.code ~= 0 then
    return nil
  end
  return M.trim(result.stdout)
end

function M.system(command, opts)
  opts = opts or {}
  local result = vim.system(command, vim.tbl_extend("force", {
    text = true,
  }, opts)):wait()
  return {
    code = result.code,
    stdout = result.stdout or "",
    stderr = result.stderr or "",
  }
end

function M.system_ok(command, opts)
  local result = M.system(command, opts)
  return result.code == 0, result
end

function M.relative_path(root, path)
  if not root or root == "" then
    return path
  end
  local prefix = root .. "/"
  if vim.startswith(path, prefix) then
    return path:sub(#prefix + 1)
  end
  return path
end

function M.write_temp(prefix, content)
  local path = vim.fn.tempname() .. "_" .. prefix
  M.write_file(path, content or "")
  return path
end

function M.remove_file(path)
  if path and M.file_exists(path) then
    pcall(vim.uv.fs_unlink, path)
  end
end

function M.list_files(root)
  if M.command_exists("rg") then
    local ok, result = M.system_ok({ "rg", "--files" }, {
      cwd = root,
    })
    if ok then
      local files = {}
      for _, line in ipairs(vim.split(M.trim(result.stdout), "\n", { plain = true })) do
        if line ~= "" then
          table.insert(files, line)
        end
      end
      return files
    end
  end

  local files = {}
  local function walk(path, prefix)
    local handle = vim.uv.fs_scandir(path)
    if not handle then
      return
    end
    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if name ~= ".git" then
        local rel = prefix ~= "" and (prefix .. "/" .. name) or name
        local full = path .. "/" .. name
        if kind == "file" then
          table.insert(files, rel)
        elseif kind == "directory" then
          walk(full, rel)
        end
      end
    end
  end

  walk(root, "")
  table.sort(files)
  return files
end

function M.mode_is_visual()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

function M.mode_is_normal()
  return vim.api.nvim_get_mode().mode == "n"
end

function M.capture_notifications(fn)
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg, level, opts)
    table.insert(messages, {
      msg = msg,
      level = level,
      opts = opts,
    })
  end
  local ok, result = pcall(fn)
  vim.notify = original
  return ok, result, messages
end

return M
