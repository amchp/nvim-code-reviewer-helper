local specs = require("code_review_helper_test.specs").tests()

local M = {}

function M.run()
  local failures = {}

  for _, spec in ipairs(specs) do
    local ok, err = pcall(spec.run)
    if ok then
      print("PASS " .. spec.name)
    else
      print("FAIL " .. spec.name)
      print(err)
      table.insert(failures, {
        name = spec.name,
        err = err,
      })
    end
  end

  if #failures > 0 then
    error(string.format("%d tests failed", #failures))
  end
end

return M
