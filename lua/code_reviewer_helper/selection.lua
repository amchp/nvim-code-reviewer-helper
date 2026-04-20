local util = require("code_reviewer_helper.util")

local M = {}

local symbol_patterns = {
  "function",
  "method",
  "class",
  "interface",
  "struct",
}

local function get_mark(mark)
  local pos = vim.fn.getpos(mark)
  return {
    bufnr = pos[1],
    row = pos[2],
    col = pos[3],
  }
end

local function current_visual_range(bufnr)
  local anchor = vim.fn.getpos("v")
  local cursor = vim.api.nvim_win_get_cursor(0)
  return {
    start_ = {
      bufnr = anchor[1],
      row = anchor[2],
      col = anchor[3],
    },
    finish = {
      bufnr = bufnr,
      row = cursor[1],
      col = cursor[2] + 1,
    },
  }
end

local function normalize_range(start_pos, end_pos)
  if start_pos.row > end_pos.row or
    (start_pos.row == end_pos.row and start_pos.col > end_pos.col)
  then
    return end_pos, start_pos
  end
  return start_pos, end_pos
end

local function selection_mode()
  if util.mode_is_visual() then
    return vim.fn.mode()
  end
  return vim.fn.visualmode()
end

local function slice_charwise(lines, start_row, start_col, end_row, end_col)
  local selected = {}
  for idx = start_row, end_row do
    local line = lines[idx]
    if idx == start_row and idx == end_row then
      table.insert(selected, string.sub(line, start_col, end_col))
    elseif idx == start_row then
      table.insert(selected, string.sub(line, start_col))
    elseif idx == end_row then
      table.insert(selected, string.sub(line, 1, end_col))
    else
      table.insert(selected, line)
    end
  end
  return selected
end

local function slice_blockwise(lines, start_row, start_col, end_row, end_col)
  local selected = {}
  local left_col = math.min(start_col, end_col)
  local right_col = math.max(start_col, end_col)
  for idx = start_row, end_row do
    table.insert(selected, string.sub(lines[idx], left_col, right_col))
  end
  return selected
end

local function slice_selection(lines, start_row, start_col, end_row, end_col, mode)
  if mode == "V" then
    return vim.list_slice(lines, start_row, end_row)
  end

  if mode == "\22" then
    return slice_blockwise(lines, start_row, start_col, end_row, end_col)
  end

  return slice_charwise(lines, start_row, start_col, end_row, end_col)
end

local function find_symbol()
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local ok_tree, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok_tree or not tree then
    return nil
  end
  local node = tree:root():named_descendant_for_range(row, 0, row, 0)
  while node do
    local type_ = node:type()
    for _, pattern in ipairs(symbol_patterns) do
      if type_:find(pattern, 1, true) then
        return type_
      end
    end
    node = node:parent()
  end
  return nil
end

local function collect_diagnostics(bufnr, start_row, end_row)
  local diagnostics = vim.diagnostic.get(bufnr)
  local results = {}
  for _, item in ipairs(diagnostics) do
    local row = item.lnum + 1
    if row >= start_row and row <= end_row then
      table.insert(results, {
        row = row,
        col = item.col + 1,
        severity = vim.diagnostic.severity[item.severity] or "UNKNOWN",
        message = item.message,
      })
    end
  end
  return results
end

function M.capture(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos
  local end_pos

  if util.mode_is_visual() then
    local visual = current_visual_range(bufnr)
    start_pos = visual.start_
    end_pos = visual.finish
  else
    start_pos = get_mark("'<")
    end_pos = get_mark("'>")
  end

  if start_pos.row == 0 or end_pos.row == 0 then
    return nil, "No visual selection found. Select code first and rerun :CRHExplain."
  end

  if start_pos.bufnr ~= 0 and start_pos.bufnr ~= bufnr then
    return nil, "No visual selection found. Select code first and rerun :CRHExplain."
  end

  if opts.require_visual_mode and not util.mode_is_visual() and not opts.allow_marks then
    return nil, "A live visual selection is required for this action."
  end

  start_pos, end_pos = normalize_range(start_pos, end_pos)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local mode = selection_mode()
  local selected = slice_selection(
    lines,
    start_pos.row,
    start_pos.col,
    end_pos.row,
    end_pos.col,
    mode
  )

  if #selected > opts.max_selection_lines then
    return nil, string.format(
      "Selection is too large (%d lines). Limit is %d lines.",
      #selected,
      opts.max_selection_lines
    )
  end

  local surrounding = opts.surrounding_lines or 0
  local before_start = math.max(1, start_pos.row - surrounding)
  local after_end = math.min(#lines, end_pos.row + surrounding)
  local before = vim.list_slice(lines, before_start, start_pos.row - 1)
  local after = vim.list_slice(lines, end_pos.row + 1, after_end)

  local data = {
    bufnr = bufnr,
    path = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    range = {
      start_row = start_pos.row,
      start_col = start_pos.col,
      end_row = end_pos.row,
      end_col = end_pos.col,
    },
    selected_lines = selected,
    surrounding_lines = {
      before = before,
      after = after,
    },
  }

  if opts.include_symbol_context then
    data.symbol = find_symbol()
  end

  if opts.include_diagnostics then
    data.diagnostics = collect_diagnostics(bufnr, start_pos.row, end_pos.row)
  else
    data.diagnostics = {}
  end

  return data
end

return M
