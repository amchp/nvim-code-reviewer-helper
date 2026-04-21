local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}
local split_augroup = vim.api.nvim_create_augroup("CodeReviewerHelperSplit", { clear = true })

local function calc_width(width)
  if width <= 1 then
    return math.max(40, math.floor(vim.o.columns * width))
  end
  return width
end

local function clear_state()
  state.split_winid = nil
  state.split_bufnr = nil
  state.split_tabpage = nil
  state.current_response_id = nil
end

local function restore_guide_layout(immediate)
  local ok, guide = pcall(require, "code_reviewer_helper.ui.guide")
  if not ok or type(guide.refresh_layout) ~= "function" then
    return
  end
  if immediate then
    pcall(guide.refresh_layout)
    return
  end
  vim.schedule(function()
    pcall(guide.refresh_layout)
  end)
end

local function next_entry()
  if not state.current_response_id then
    return nil
  end
  return require("code_reviewer_helper.history").neighbor(state.current_response_id, 1)
end

function M.should_auto_open(tabpage)
  if not state.config or not state.config.ui.auto_open_on_complete then
    return false
  end
  if not util.mode_is_normal() then
    return false
  end
  if tabpage then
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return false
    end
    if vim.api.nvim_get_current_tabpage() ~= tabpage then
      return false
    end
  end
  return true
end

local function handoff_after_window_close()
  local entry = next_entry()
  local config = state.config
  local closed_tabpage = state.split_tabpage
  clear_state()
  if not entry or not config then
    return false
  end
  vim.schedule(function()
    if not M.should_auto_open(closed_tabpage) then
      restore_guide_layout()
      return
    end
    M.render(entry, config)
  end)
  return true
end

vim.api.nvim_create_autocmd("WinClosed", {
  group = split_augroup,
  callback = function(args)
    local winid = tonumber(args.match)
    if not state.split_winid or winid ~= state.split_winid then
      return
    end

    if state.suppress_split_handoff then
      state.suppress_split_handoff = false
      clear_state()
      return
    end

    if not handoff_after_window_close() then
      restore_guide_layout()
    end
  end,
})

local function ensure_window(config)
  if config.ui.reuse_window and state.split_winid and vim.api.nvim_win_is_valid(state.split_winid) then
    vim.api.nvim_win_set_width(state.split_winid, calc_width(config.ui.width))
    return state.split_winid, state.split_bufnr
  end

  local current = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, calc_width(config.ui.width))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_set_current_win(current)

  state.split_winid = win
  state.split_bufnr = buf
  state.split_tabpage = vim.api.nvim_win_get_tabpage(win)
  return win, buf
end

local function set_response_buffer_name(buf, entry_id)
  local name = "crh://response/" .. entry_id
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and existing ~= buf and vim.api.nvim_buf_is_valid(existing) then
    pcall(vim.api.nvim_buf_delete, existing, { force = true })
  end
  vim.api.nvim_buf_set_name(buf, name)
end

local function apply_window_options(win, config)
  vim.wo[win].wrap = config.ui.wrap
  vim.wo[win].linebreak = config.ui.linebreak
  vim.wo[win].breakindent = config.ui.breakindent
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
end

local function apply_buffer_options(buf)
  vim.bo[buf].modifiable = true
  vim.keymap.set("n", "q", function()
    M.close_or_next()
  end, {
    buffer = buf,
    nowait = true,
    silent = true,
  })
end

local function extend_preview(lines, entry)
  table.insert(lines, "## Code Preview")
  table.insert(lines, "")
  table.insert(lines, "```" .. (entry.filetype or ""))
  for _, line in ipairs(vim.split(entry.selection_preview or "", "\n", { plain = true })) do
    table.insert(lines, line)
  end
  table.insert(lines, "```")
end

function M.render(entry, config, opts)
  opts = opts or {}
  local history = require("code_reviewer_helper.history")
  local current = vim.api.nvim_get_current_win()
  local win, buf = ensure_window(config)
  state.split_tabpage = vim.api.nvim_win_get_tabpage(win)
  apply_window_options(win, config)
  apply_buffer_options(buf)
  local lines = {}

  if entry.status ~= "success" then
    local _, index = history.find(entry.id)
    local entries = history.list()
    lines = {
      "# Code Review Helper",
      "",
      string.format("- Status: %s", entry.status),
      string.format("- File: %s", entry.path),
      string.format("- Range: %d:%d to %d:%d", entry.range.start_row, entry.range.start_col, entry.range.end_row, entry.range.end_col),
      string.format("- Created: %s", entry.created_at),
      string.format("- Queue Position: %d/%d", index or 0, #entries),
      "",
      "## Saved Questions",
      "",
    }

    for item_index, item in ipairs(entries) do
      local marker = item.id == entry.id and "*" or "-"
      table.insert(
        lines,
        string.format(
          "%s %d. %s",
          marker,
          item_index,
          item.question
        )
      )
    end
  end

  vim.list_extend(lines, {
    "## Question",
    "",
    entry.question,
    "",
  })
  extend_preview(lines, entry)
  vim.list_extend(lines, {
    "",
    "## Response",
    "",
  })

  for _, line in ipairs(vim.split(entry.response_markdown or "", "\n", { plain = true })) do
    table.insert(lines, line)
  end

  if entry.status ~= "success" and entry.stderr and entry.stderr ~= "" then
    table.insert(lines, "")
    table.insert(lines, "## stderr")
    table.insert(lines, "")
    for _, line in ipairs(vim.split(entry.stderr, "\n", { plain = true })) do
      table.insert(lines, line)
    end
  end

  set_response_buffer_name(buf, entry.id)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end

  if opts.focus ~= false and config.ui.auto_open_on_complete and state.split_winid and vim.api.nvim_win_is_valid(state.split_winid) then
    vim.api.nvim_set_current_win(state.split_winid)
  elseif vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end

  state.current_response_id = entry.id
end

function M.is_open()
  return state.split_winid ~= nil and vim.api.nvim_win_is_valid(state.split_winid)
end

function M.close()
  if M.is_open() then
    state.suppress_split_handoff = true
    pcall(vim.api.nvim_win_close, state.split_winid, true)
  end
  clear_state()
  state.suppress_split_handoff = false
  restore_guide_layout(true)
end

function M.close_or_next()
  local entry = next_entry()
  if entry then
    M.render(entry, state.config)
    return
  end
  M.close()
end

return M
