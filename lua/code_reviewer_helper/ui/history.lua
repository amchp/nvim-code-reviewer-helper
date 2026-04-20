local history = require("code_reviewer_helper.history")

local M = {}

function M.pick(callback)
  local entries = history.list()
  if #entries == 0 then
    vim.notify("No saved responses yet", vim.log.levels.INFO, {
      title = "code-reviewer-helper",
    })
    return
  end

  local items = {}
  for _, entry in ipairs(entries) do
    table.insert(items, {
      entry = entry,
      label = string.format(
        "%s [%s] %s:%d-%d",
        entry.status,
        entry.id,
        vim.fn.fnamemodify(entry.path, ":t"),
        entry.range.start_row,
        entry.range.end_row
      ),
    })
  end

  vim.ui.select(items, {
    prompt = "Saved responses",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      callback(choice.entry)
    end
  end)
end

return M
