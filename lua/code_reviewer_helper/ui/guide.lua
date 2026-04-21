local guide_history = require("code_reviewer_helper.guide.history")
local state = require("code_reviewer_helper.state")
local util = require("code_reviewer_helper.util")

local M = {}
local GUIDE_LIST_RATIO = 0.2
local GUIDE_MIN_LIST_WIDTH = 18
local GUIDE_MIN_CONTENT_WIDTH = 30

local native = {
  list_winid = nil,
  primary_winid = nil,
  secondary_winid = nil,
}

local function clear_native_state()
  native.list_winid = nil
  native.primary_winid = nil
  native.secondary_winid = nil
end

local function clamp(value, minimum, maximum)
  if maximum < minimum then
    return minimum
  end
  return math.min(math.max(value, minimum), maximum)
end

local function configure_scratch_buffer(buf, filetype)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = filetype or ""
end

local function set_buffer_name(buf, name)
  local ok = pcall(vim.api.nvim_buf_set_name, buf, name)
  if ok then
    return buf
  end

  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and existing ~= buf and vim.api.nvim_buf_is_valid(existing) then
    if vim.fn.bufwinid(existing) == -1 then
      pcall(vim.api.nvim_buf_delete, existing, { force = true })
      ok = pcall(vim.api.nvim_buf_set_name, buf, name)
      if ok then
        return buf
      end
    else
      return existing
    end
  end

  vim.api.nvim_buf_set_name(buf, string.format("%s/%s", name, tostring(vim.uv.hrtime())))
  return buf
end

local function named_scratch_buffer(name, filetype)
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
    configure_scratch_buffer(existing, filetype)
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, true)
  configure_scratch_buffer(buf, filetype)
  return set_buffer_name(buf, name)
end

local function close_guide_tab()
  local tabpage = state.guide_tabpage
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end

  local current = vim.api.nvim_get_current_tabpage()
  local restore = current ~= tabpage and vim.api.nvim_tabpage_is_valid(current)
  pcall(vim.api.nvim_set_current_tabpage, tabpage)
  pcall(vim.cmd, "tabclose")
  if restore and vim.api.nvim_tabpage_is_valid(current) then
    pcall(vim.api.nvim_set_current_tabpage, current)
  end
end

local function restore_return_target()
  local target = state.guide_return_target
  state.guide_return_target = nil
  if not target then
    return
  end

  if target.tabpage and vim.api.nvim_tabpage_is_valid(target.tabpage) then
    pcall(vim.api.nvim_set_current_tabpage, target.tabpage)
  end

  if target.winid and vim.api.nvim_win_is_valid(target.winid) then
    pcall(vim.api.nvim_set_current_win, target.winid)
    if target.cursor then
      pcall(vim.api.nvim_win_set_cursor, target.winid, target.cursor)
    end
    return
  end

  if target.path and target.path ~= "" then
    pcall(vim.cmd, "edit " .. vim.fn.fnameescape(target.path))
    if target.cursor then
      pcall(vim.api.nvim_win_set_cursor, 0, target.cursor)
    end
    return
  end

  if target.bufnr and vim.api.nvim_buf_is_valid(target.bufnr) then
    pcall(vim.api.nvim_set_current_buf, target.bufnr)
  end
end

local function clear_guide_state()
  state.guide_tabpage = nil
  state.guide_list_bufnr = nil
  state.guide_current_index = nil
  clear_native_state()
end

local function session_item(session, index)
  return session.items[index]
end

local function session_resume_index(session)
  if not session or not session.items or #session.items == 0 then
    return 1
  end

  local index = tonumber(session.resume_index) or 1
  if session.resume_path and session.resume_path ~= "" then
    for item_index, item in ipairs(session.items) do
      if item.path == session.resume_path then
        index = item_index
        break
      end
    end
  end

  return clamp(index, 1, #session.items)
end

local function persist_session_progress()
  local session = state.guide_session
  if not session or not session.items or #session.items == 0 then
    return
  end
  if not state.guide_tabpage or not vim.api.nvim_tabpage_is_valid(state.guide_tabpage) then
    return
  end
  if not state.guide_current_index then
    return
  end

  local index = session_resume_index({
    items = session.items,
    resume_index = state.guide_current_index,
  })
  local item = session_item(session, index)
  session.resume_index = index
  session.resume_path = item and item.path or nil
  guide_history.update(session)
end

local function set_local_maps(buf)
  vim.keymap.set("n", "<Tab>", function()
    M.next_item()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<S-Tab>", function()
    M.prev_item()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "gp", function()
    M.open_plan()
  end, { buffer = buf, nowait = true, silent = true })
end

local function set_plan_map(buf)
  vim.keymap.set("n", "gp", function()
    M.open_plan()
  end, { buffer = buf, nowait = true, silent = true })
end

local function ensure_plan_buffer(session)
  local name = "crh://guide-plan/" .. session.id
  if state.guide_plan_bufnr and vim.api.nvim_buf_is_valid(state.guide_plan_bufnr) then
    local current_name = vim.api.nvim_buf_get_name(state.guide_plan_bufnr)
    if current_name == name then
      return state.guide_plan_bufnr
    end
    pcall(vim.api.nvim_buf_delete, state.guide_plan_bufnr, { force = true })
  end

  local buf = named_scratch_buffer(name, "markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(session.plan_markdown, "\n", { plain = true }))
  vim.bo[buf].modifiable = false
  set_local_maps(buf)
  state.guide_plan_bufnr = buf
  return buf
end

local function file_icon(path)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok and devicons and type(devicons.get_icon) == "function" then
    local icon = devicons.get_icon(vim.fn.fnamemodify(path, ":t"), vim.fn.fnamemodify(path, ":e"), {
      default = true,
    })
    if icon and icon ~= "" then
      return icon
    end
  end
  return "[f]"
end

local function render_list(session)
  local buf = state.guide_list_bufnr
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {
    "# Guided Review",
    "",
    session.summary,
    "",
  }

  for index, item in ipairs(session.items) do
    local marker = index == state.guide_current_index and ">" or " "
    table.insert(lines, string.format("%s [%s] %s %s", marker, item.status, file_icon(item.path), item.path))
    table.insert(lines, "  " .. item.reason)
    table.insert(lines, "")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local cursor_line = 5 + ((state.guide_current_index or 1) - 1) * 3
  if native.list_winid and vim.api.nvim_win_is_valid(native.list_winid) then
    vim.api.nvim_win_set_cursor(native.list_winid, { math.min(cursor_line, #lines), 0 })
  end
end

local function new_scratch_buffer(name, filetype, lines)
  local buf = named_scratch_buffer(name, filetype)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  set_local_maps(buf)
  return buf
end

local function filetype_for_path(path)
  return vim.filetype.match({ filename = path }) or ""
end

local function git_show_lines(root, path)
  local result = util.system({ "git", "-C", root, "show", "HEAD:" .. path })
  if result.code ~= 0 then
    return nil
  end
  return vim.split(result.stdout, "\n", { plain = true })
end

local function working_lines(root, path)
  return util.read_lines(root .. "/" .. path)
end

local function render_repo_item(session, item)
  if not native.primary_winid or not vim.api.nvim_win_is_valid(native.primary_winid) then
    return
  end

  vim.api.nvim_set_current_win(native.primary_winid)
  local path = session.workspace_root .. "/" .. item.path
  if util.file_exists(path) then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    set_local_maps(vim.api.nvim_get_current_buf())
  else
    local buf = new_scratch_buffer(
      "crh://guide-missing/" .. session.id .. "/" .. item.path,
      filetype_for_path(item.path),
      { "File is missing: " .. item.path }
    )
    vim.api.nvim_win_set_buf(native.primary_winid, buf)
  end
end

local function render_change_item(session, item)
  if not native.primary_winid or not vim.api.nvim_win_is_valid(native.primary_winid) then
    return
  end

  local filetype = filetype_for_path(item.path)
  local left_lines = git_show_lines(session.workspace_root, item.old_path or item.path)
  local right_lines = working_lines(session.workspace_root, item.path)

  if item.status == "untracked" or item.status == "added" then
    left_lines = { "[No file on left side]" }
  elseif item.status == "deleted" then
    right_lines = { "[No file on right side]" }
  elseif not left_lines then
    left_lines = { "[Unable to load HEAD version]" }
  end
  if not right_lines then
    right_lines = { "[Unable to load working tree version]" }
  end

  local left_buf = new_scratch_buffer(
    "crh://guide-left/" .. session.id .. "/" .. item.path,
    filetype,
    left_lines
  )
  vim.api.nvim_win_set_buf(native.primary_winid, left_buf)

  if not native.secondary_winid or not vim.api.nvim_win_is_valid(native.secondary_winid) then
    return
  end

  local right_buf = new_scratch_buffer(
    "crh://guide-right/" .. session.id .. "/" .. item.path,
    filetype,
    right_lines
  )
  vim.api.nvim_win_set_buf(native.secondary_winid, right_buf)

  vim.api.nvim_win_call(native.primary_winid, function()
    vim.cmd("silent! diffoff!")
  end)
  vim.api.nvim_win_call(native.secondary_winid, function()
    vim.cmd("silent! diffoff!")
  end)
  vim.api.nvim_win_call(native.primary_winid, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(native.secondary_winid, function()
    vim.cmd("diffthis")
  end)
end

local function render_current_native()
  local session = state.guide_session
  if not session then
    return
  end
  local item = session_item(session, state.guide_current_index or 1)
  if not item then
    return
  end

  render_list(session)
  if session.mode == "changes" then
    render_change_item(session, item)
  else
    render_repo_item(session, item)
  end
end

local function list_index_from_cursor()
  if not native.list_winid or not vim.api.nvim_win_is_valid(native.list_winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(native.list_winid)[1]
  if row < 5 then
    return nil
  end
  local index = math.floor((row - 5) / 3) + 1
  if state.guide_session and index >= 1 and index <= #state.guide_session.items then
    return index
  end
  return nil
end

local function apply_native_layout()
  if not native.list_winid or not vim.api.nvim_win_is_valid(native.list_winid) then
    return
  end

  local has_secondary = native.secondary_winid and vim.api.nvim_win_is_valid(native.secondary_winid)
  local total_width = 0
  for _, winid in ipairs({ native.list_winid, native.primary_winid, native.secondary_winid }) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      total_width = total_width + vim.api.nvim_win_get_width(winid)
    end
  end

  local content_wins = has_secondary and 2 or 1
  local max_list_width = total_width - (content_wins * GUIDE_MIN_CONTENT_WIDTH)
  local target_width = clamp(
    math.floor(total_width * GUIDE_LIST_RATIO),
    GUIDE_MIN_LIST_WIDTH,
    math.max(GUIDE_MIN_LIST_WIDTH, max_list_width)
  )

  vim.api.nvim_win_set_width(native.list_winid, target_width)
  if not native.primary_winid or not vim.api.nvim_win_is_valid(native.primary_winid) then
    return
  end

  local content_width = math.max(total_width - target_width, content_wins * GUIDE_MIN_CONTENT_WIDTH)
  if has_secondary then
    local primary_width = math.floor(content_width / 2)
    local secondary_width = content_width - primary_width
    vim.api.nvim_win_set_width(native.primary_winid, primary_width)
    vim.api.nvim_win_set_width(native.secondary_winid, secondary_width)
    return
  end

  vim.api.nvim_win_set_width(native.primary_winid, content_width)
end

function M.refresh_layout()
  if not state.guide_tabpage or not vim.api.nvim_tabpage_is_valid(state.guide_tabpage) then
    return
  end
  apply_native_layout()
end

local function open_native_tab(session)
  vim.cmd("tabnew")
  state.guide_tabpage = vim.api.nvim_get_current_tabpage()

  local list_buf = named_scratch_buffer("crh://guide-list/" .. session.id, "markdown")
  state.guide_list_bufnr = list_buf
  native.list_winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(native.list_winid, list_buf)
  set_local_maps(list_buf)
  vim.keymap.set("n", "<CR>", function()
    local index = list_index_from_cursor()
    if index then
      state.guide_current_index = index
      render_current_native()
    end
  end, { buffer = list_buf, nowait = true, silent = true })

  vim.cmd("botright vsplit")
  native.primary_winid = vim.api.nvim_get_current_win()

  if session.mode == "changes" then
    vim.cmd("botright vsplit")
    native.secondary_winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(native.list_winid)
  end

  apply_native_layout()

  state.guide_current_index = state.guide_current_index or session_resume_index(session)
  render_current_native()
  vim.api.nvim_set_current_win(native.list_winid)
end

local function install_diffview_maps()
  if not state.guide_tabpage or not vim.api.nvim_tabpage_is_valid(state.guide_tabpage) then
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.guide_tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    set_plan_map(buf)
  end
end

local function build_diffview_files(session)
  local working = {}
  local selected_index = session_resume_index(session)
  for index, item in ipairs(session.items) do
    table.insert(working, {
      path = item.path,
      oldpath = item.old_path,
      status = item.status == "untracked" and "?" or item.status:sub(1, 1):upper(),
      left_null = item.status == "untracked" or item.status == "added",
      right_null = item.status == "deleted",
      selected = index == selected_index,
    })
  end
  return {
    working = working,
    staged = {},
  }
end

local function open_with_diffview(session)
  local ok_rev, rev_mod = pcall(require, "diffview.rev")
  local ok_view, view_mod = pcall(require, "diffview.api.views.diff.diff_view")
  local ok_lib, lib = pcall(require, "diffview.lib")
  if not (ok_rev and ok_view and ok_lib) then
    return false
  end

  local Rev = rev_mod.Rev
  local RevType = rev_mod.RevType
  local CDiffView = view_mod.CDiffView
  local files = build_diffview_files(session)

  local function get_file_data(kind, path, split)
    if kind ~= "working" then
      return nil
    end
    local selected
    for _, item in ipairs(session.items) do
      if item.path == path then
        selected = item
        break
      end
    end
    if not selected then
      return nil
    end
    if split == "left" then
      if selected.status == "untracked" or selected.status == "added" then
        return nil
      end
      return git_show_lines(session.workspace_root, selected.old_path or selected.path)
    end
    if selected.status == "deleted" then
      return nil
    end
    return working_lines(session.workspace_root, selected.path)
  end

  local view = CDiffView({
    git_root = session.workspace_root,
    left = Rev(RevType.COMMIT, "HEAD"),
    right = Rev(RevType.LOCAL),
    files = files,
    update_files = function()
      return files
    end,
    get_file_data = get_file_data,
  })
  if view.panel then
    view.panel.config_producer = vim.tbl_deep_extend("force", {}, view.panel.config_producer or {}, {
      width = clamp(
        math.floor(vim.o.columns * GUIDE_LIST_RATIO),
        GUIDE_MIN_LIST_WIDTH,
        math.max(GUIDE_MIN_LIST_WIDTH, vim.o.columns - (2 * GUIDE_MIN_CONTENT_WIDTH))
      ),
    })
  end

  lib.add_view(view)
  view:open()
  state.guide_tabpage = vim.api.nvim_get_current_tabpage()
  state.guide_current_index = session_resume_index(session)
  install_diffview_maps()
  return true
end

function M.open(session, config)
  persist_session_progress()
  close_guide_tab()
  clear_guide_state()
  state.guide_session = session
  state.guide_current_index = session_resume_index(session)
  ensure_plan_buffer(session)

  if session.mode == "changes" and config.guide.use_diffview_if_available then
    local ok = pcall(open_with_diffview, session)
    if ok and state.guide_tabpage then
      return
    end
  end

  open_native_tab(session)
end

function M.next_item()
  if not state.guide_session then
    return
  end
  local next_index = math.min((state.guide_current_index or 1) + 1, #state.guide_session.items)
  state.guide_current_index = next_index
  render_current_native()
end

function M.prev_item()
  if not state.guide_session then
    return
  end
  local prev_index = math.max((state.guide_current_index or 1) - 1, 1)
  state.guide_current_index = prev_index
  render_current_native()
end

function M.close()
  persist_session_progress()
  if state.guide_tabpage and vim.api.nvim_tabpage_is_valid(state.guide_tabpage) then
    pcall(vim.api.nvim_set_current_tabpage, state.guide_tabpage)
    pcall(vim.cmd, "tabclose")
  end
  clear_guide_state()
  restore_return_target()
end

function M.open_plan()
  local session = state.guide_session
  if not session then
    util.notify("No active guide session", vim.log.levels.WARN)
    return
  end

  local buf = ensure_plan_buffer(session)
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  M.refresh_layout()
end

function M.show_parse_failure(raw_response, err)
  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Guide Parse Failure",
    "",
    "- Error: " .. err,
    "",
    "## Raw Response",
    "",
  })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(raw_response or "", "\n", { plain = true }))
  set_local_maps(buf)
end

return M
