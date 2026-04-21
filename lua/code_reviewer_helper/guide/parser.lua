local util = require("code_reviewer_helper.util")

local M = {}

local valid_status = {
  modified = true,
  added = true,
  deleted = true,
  renamed = true,
  untracked = true,
  repo = true,
}

local function skip_string(text, index)
  index = index + 1
  while index <= #text do
    local char = text:sub(index, index)
    if char == "\\" then
      index = index + 2
    elseif char == '"' then
      return index + 1
    else
      index = index + 1
    end
  end
  return nil
end

local function extract_first_json_object(text, start_index)
  local open_index = text:find("{", start_index, true)
  if not open_index then
    return nil
  end

  local depth = 0
  local index = open_index
  while index <= #text do
    local char = text:sub(index, index)
    if char == '"' then
      index = skip_string(text, index)
      if not index then
        return nil
      end
    elseif char == "{" then
      depth = depth + 1
      index = index + 1
    elseif char == "}" then
      depth = depth - 1
      index = index + 1
      if depth == 0 then
        return text:sub(open_index, index - 1), open_index, index - 1
      end
    else
      index = index + 1
    end
  end

  return nil
end

local function parse_json_block(response)
  local fenced_start, fenced_content_start = response:find("```json%s*")
  if fenced_start then
    local json, _, json_end = extract_first_json_object(response, fenced_content_start + 1)
    if json then
      return json, json_end
    end
  end

  local json, _, json_end = extract_first_json_object(response, 1)
  if json then
    return json, json_end
  end

  return nil
end

local function parse_markdown(response)
  local markdown = response:match("```json%s*.-%s*```%s*(# Review Order[\r\n].*)")
  if markdown then
    return markdown
  end
  return response:match("(# Review Order[\r\n].*)")
end

function M.parse(response, context)
  local json_block = parse_json_block(response or "")
  if not json_block then
    return nil, "missing fenced json block"
  end

  local payload = util.json_decode(json_block)
  if type(payload) ~= "table" then
    return nil, "invalid json payload"
  end
  if payload.mode ~= "changes" and payload.mode ~= "repo" then
    return nil, "invalid mode"
  end
  if type(payload.summary) ~= "string" or payload.summary == "" then
    return nil, "missing summary"
  end
  if type(payload.items) ~= "table" or #payload.items == 0 then
    return nil, "missing items"
  end

  local deduped = {}
  local seen = {}
  for _, item in ipairs(payload.items) do
    if type(item) ~= "table" then
      return nil, "invalid item"
    end
    if type(item.path) ~= "string" or item.path == "" then
      return nil, "item path must be a non-empty string"
    end
    if type(item.reason) ~= "string" or item.reason == "" then
      return nil, "item reason must be a non-empty string"
    end
    if not valid_status[item.status] then
      return nil, "item status is invalid"
    end
    if item.old_path == vim.NIL then
      item.old_path = nil
    end
    if item.old_path ~= nil and type(item.old_path) ~= "string" then
      return nil, "item old_path must be nil or string"
    end
    if item.status ~= "deleted" and not context.valid_paths[item.path] then
      return nil, "item path does not exist in repo inventory: " .. item.path
    end
    if not seen[item.path] then
      seen[item.path] = true
      table.insert(deduped, {
        path = item.path,
        reason = item.reason,
        status = item.status,
        old_path = item.old_path,
      })
    end
  end

  local plan_markdown = parse_markdown(response or "")
  if not plan_markdown then
    return nil, "missing markdown plan"
  end

  return {
    mode = payload.mode,
    summary = payload.summary,
    items = deduped,
    plan_markdown = plan_markdown,
  }
end

return M
