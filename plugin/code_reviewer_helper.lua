local ok, helper = pcall(require, "code_reviewer_helper")
if not ok then
  return
end

vim.api.nvim_create_user_command("CRHExplain", function(opts)
  helper.explain({
    from_visual_command = opts.range > 0,
  })
end, {
  desc = "Explain the current selection, or ask a repo question about the current file",
  range = true,
})

vim.api.nvim_create_user_command("CRHAskFile", function()
  helper.ask_current_file()
end, {
  desc = "Ask a required question about the current file",
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

vim.api.nvim_create_user_command("CRHBtcaAddRepo", function(opts)
  helper.add_btca_repo(opts.args ~= "" and opts.args or nil)
end, {
  desc = "Add a BTCA repository for the current workspace from a git URL",
  nargs = "?",
})

vim.api.nvim_create_user_command("CRHHealth", function()
  helper.health()
end, {
  desc = "Run plugin health checks",
})

vim.api.nvim_create_user_command("CRHReviewCodebase", function()
  helper.review_codebase()
end, {
  desc = "Start a Codebase Review",
})

vim.api.nvim_create_user_command("CRHReviewGitChanges", function()
  helper.review_git_changes()
end, {
  desc = "Start a Git Changes Review",
})

vim.api.nvim_create_user_command("CRHGuideHistory", function()
  helper.open_guide_history()
end, {
  desc = "Open Review Session history",
})

vim.api.nvim_create_user_command("CRHGuideOpenLast", function()
  helper.open_last_guide()
end, {
  desc = "Open the last Review Session",
})

vim.api.nvim_create_user_command("CRHGuideHistoryClear", function()
  helper.clear_guide_history()
end, {
  desc = "Clear Review Session history for the current workspace",
})

vim.api.nvim_create_user_command("CRHGuideClose", function()
  helper.close_guide()
end, {
  desc = "Close the current Review Session and save the resume position",
})

vim.api.nvim_create_user_command("CRHGuidePlan", function()
  helper.open_guide_plan()
end, {
  desc = "Open the current Review Overview",
})
