local M = {}

local defaults = {
  codex = {
    bin = "codex",
    model = "gpt-5.4-mini",
    sandbox = "workspace-write",
    ephemeral = true,
    use_web_search = true,
    extra_args = {},
  },
  btca = {
    enabled = true,
    sandbox_dir = vim.fn.expand("~/.btca/agent/sandbox"),
    skill_path = vim.fn.expand("~/.codex/skills/btca-local/SKILL.md"),
    fallback_prompt = true,
    repositories = {},
    max_repositories = 5,
    auto_sync = false,
  },
  context = {
    md_files = { "AGENTS.md", "README.md" },
    surrounding_lines = 40,
    max_selection_lines = 200,
    include_diagnostics = true,
    include_symbol_context = true,
    max_doc_bytes = 32768,
  },
  ui = {
    split = "right",
    width = 0.42,
    auto_open_on_complete = true,
    reuse_window = true,
    wrap = true,
    linebreak = true,
    breakindent = true,
  },
  history = {
    persist = true,
    max_entries = 100,
  },
  guide = {
    persist = true,
    max_sessions = 30,
    repo_mode_max_files = 20,
    include_untracked = true,
    use_diffview_if_available = true,
    max_doc_bytes = 32768,
    max_diff_bytes_per_file = 16000,
  },
  prompt = {
    default_question = "Explain this code. Focus on purpose, control flow, dependencies, and edge cases.",
    require_visual_mode = true,
  },
}

local function validate_table(value, name)
  if type(value) ~= "table" then
    error(string.format("%s must be a table", name))
  end
end

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.normalize(user_opts)
  local opts = vim.tbl_deep_extend("force", M.defaults(), user_opts or {})

  validate_table(opts.codex, "codex")
  validate_table(opts.btca, "btca")
  validate_table(opts.context, "context")
  validate_table(opts.ui, "ui")
  validate_table(opts.history, "history")
  validate_table(opts.guide, "guide")
  validate_table(opts.prompt, "prompt")

  if type(opts.codex.bin) ~= "string" or opts.codex.bin == "" then
    error("codex.bin must be a non-empty string")
  end
  if opts.codex.model ~= nil and type(opts.codex.model) ~= "string" then
    error("codex.model must be a string or nil")
  end
  if type(opts.codex.sandbox) ~= "string" or opts.codex.sandbox == "" then
    error("codex.sandbox must be a non-empty string")
  end
  if type(opts.codex.ephemeral) ~= "boolean" then
    error("codex.ephemeral must be a boolean")
  end
  if type(opts.codex.extra_args) ~= "table" then
    error("codex.extra_args must be a table")
  end
  if type(opts.btca.sandbox_dir) ~= "string" or opts.btca.sandbox_dir == "" then
    error("btca.sandbox_dir must be a non-empty string")
  end
  if type(opts.btca.skill_path) ~= "string" or opts.btca.skill_path == "" then
    error("btca.skill_path must be a non-empty string")
  end
  if type(opts.btca.repositories) ~= "table" then
    error("btca.repositories must be a table")
  end
  if type(opts.btca.max_repositories) ~= "number" then
    error("btca.max_repositories must be a number")
  end
  if type(opts.context.md_files) ~= "table" then
    error("context.md_files must be a table")
  end
  if type(opts.context.surrounding_lines) ~= "number" then
    error("context.surrounding_lines must be a number")
  end
  if type(opts.context.max_selection_lines) ~= "number" then
    error("context.max_selection_lines must be a number")
  end
  if type(opts.ui.width) ~= "number" then
    error("ui.width must be a number")
  end
  if type(opts.ui.wrap) ~= "boolean" then
    error("ui.wrap must be a boolean")
  end
  if type(opts.ui.linebreak) ~= "boolean" then
    error("ui.linebreak must be a boolean")
  end
  if type(opts.ui.breakindent) ~= "boolean" then
    error("ui.breakindent must be a boolean")
  end
  if type(opts.history.max_entries) ~= "number" then
    error("history.max_entries must be a number")
  end
  if type(opts.guide.max_sessions) ~= "number" then
    error("guide.max_sessions must be a number")
  end
  if type(opts.guide.repo_mode_max_files) ~= "number" then
    error("guide.repo_mode_max_files must be a number")
  end
  if type(opts.guide.include_untracked) ~= "boolean" then
    error("guide.include_untracked must be a boolean")
  end
  if type(opts.guide.use_diffview_if_available) ~= "boolean" then
    error("guide.use_diffview_if_available must be a boolean")
  end
  if type(opts.guide.max_doc_bytes) ~= "number" then
    error("guide.max_doc_bytes must be a number")
  end
  if type(opts.guide.max_diff_bytes_per_file) ~= "number" then
    error("guide.max_diff_bytes_per_file must be a number")
  end
  if type(opts.prompt.default_question) ~= "string" then
    error("prompt.default_question must be a string")
  end

  opts.btca.sandbox_dir = vim.fn.expand(opts.btca.sandbox_dir)
  opts.btca.skill_path = vim.fn.expand(opts.btca.skill_path)

  return opts
end

return M
