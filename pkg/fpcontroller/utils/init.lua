---
-- Shared utilities for the first-person controller package.
--
-- @module utils

local assertions = require("luatypechecks.assertions")

local utils = {}

---
-- ⚠️. Copy the top-level key-value pairs of a table.
-- Nested values are shared with the original table.
-- @tparam table data table to copy
-- @treturn table shallow copy of `data`
function utils.shallow_copy(data)
  assertions.is_table(data)

  local result = {}
  for key, value in pairs(data) do
    result[key] = value
  end

  return result
end

return utils
