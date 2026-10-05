---
-- Three-dimensional vector helpers used by the physics controllers.
--
-- @module vector

local assertions = require("luatypechecks.assertions")

local _MIN_LENGTH = 1e-9

local vectorutils = {}

---
-- ⚠️. Limit a vector's length while preserving its direction.
-- Near-zero vectors are returned unchanged.
-- @tparam vector value vector to limit
-- @tparam number maximum_length maximum vector length
-- @treturn vector limited vector
function vectorutils.limit_length(value, maximum_length)
  assertions.is_table(value)
  assertions.is_number(maximum_length)

  local length = value:length()
  if length <= math.max(maximum_length, _MIN_LENGTH) then
    return value
  end

  return value * (maximum_length / length)
end

return vectorutils
