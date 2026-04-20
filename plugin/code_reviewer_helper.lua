local ok, helper = pcall(require, "code_reviewer_helper")
if not ok then
  return
end

vim.api.nvim_create_user_command("CRHExplain", function()
  helper.explain_visual()
end, {
  desc = "Explain the current visual selection with Codex",
  range = true,
})

vim.api.nvim_create_user_command("CRHHistory", function()
  helper.open_history()
end, {
  desc = "Open explain request history",
})

vim.api.nvim_create_user_command("CRHOpenLast", function()
  helper.open_last()
end, {
  desc = "Open the last explain response",
})

vim.api.nvim_create_user_command("CRHNext", function()
  helper.next_response()
end, {
  desc = "Open the next saved response",
})

vim.api.nvim_create_user_command("CRHPrev", function()
  helper.prev_response()
end, {
  desc = "Open the previous saved response",
})

vim.api.nvim_create_user_command("CRHCancel", function(opts)
  local id = opts.args ~= "" and opts.args or nil
  helper.cancel(id)
end, {
  desc = "Cancel an active explain request",
  nargs = "?",
})

vim.api.nvim_create_user_command("CRHBtcaSync", function()
  helper.sync_btca()
end, {
  desc = "Sync BTCA repositories",
})

vim.api.nvim_create_user_command("CRHHealth", function()
  helper.health()
end, {
  desc = "Run plugin health checks",
})

vim.api.nvim_create_user_command("CRHGuide", function()
  helper.guide()
end, {
  desc = "Start a guided repository review session",
})

vim.api.nvim_create_user_command("CRHGuideHistory", function()
  helper.open_guide_history()
end, {
  desc = "Open guided review session history",
})

vim.api.nvim_create_user_command("CRHGuideOpenLast", function()
  helper.open_last_guide()
end, {
  desc = "Open the last guided review session",
})

vim.api.nvim_create_user_command("CRHGuidePlan", function()
  helper.open_guide_plan()
end, {
  desc = "Open the current guided review plan",
})
