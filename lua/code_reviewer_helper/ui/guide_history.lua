local history = require("code_reviewer_helper.guide.history")

local M = {}

function M.pick(callback)
  local entries = history.list()
  if #entries == 0 then
    vim.notify("No saved guide sessions yet", vim.log.levels.INFO, {
      title = "code-reviewer-helper",
    })
    return
  end

  local items = {}
  for _, entry in ipairs(entries) do
    table.insert(items, {
      entry = entry,
      label = string.format(
        "%s [%s] %s files",
        entry.mode,
        entry.id,
        #entry.items
      ),
    })
  end

  vim.ui.select(items, {
    prompt = "Saved guide sessions",
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
