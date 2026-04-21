local M = {
  config = nil,
  history = nil,
  active_jobs = {},
  split_bufnr = nil,
  split_winid = nil,
  split_tabpage = nil,
  current_response_id = nil,
  suppress_split_handoff = false,
  guide_history = nil,
  guide_session = nil,
  guide_tabpage = nil,
  guide_list_bufnr = nil,
  guide_plan_bufnr = nil,
  guide_current_index = nil,
  guide_return_target = nil,
  active_guide_jobs = {},
}

return M
