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
    local commit_label = "no git commit"
    if entry.commit and entry.commit.subject and entry.commit.subject ~= "" then
      local ref = entry.commit.short ~= "" and entry.commit.short or "HEAD"
      commit_label = string.format("%s %s", ref, entry.commit.subject)
    end
    table.insert(items, {
      entry = entry,
      label = string.format(
        "%s [%s] %s files | %s",
        entry.mode,
        entry.id,
        #entry.items,
        commit_label
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
