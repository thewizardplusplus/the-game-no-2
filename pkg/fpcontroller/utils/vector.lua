---
-- Three-dimensional vector helpers used by the physics controllers.
--
-- @module vector

local assertions = require("luatypechecks.assertions")

local _MIN_LENGTH = 1e-9

local vector = {}

---
-- ⚠️. Return the length of a vector.
-- @tparam number x vector X component
-- @tparam number y vector Y component
-- @tparam number z vector Z component
-- @treturn number vector length
function vector.length(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  return math.sqrt(x * x + y * y + z * z)
end

---
-- ⚠️. Limit a vector's length while preserving its direction.
-- Near-zero vectors are returned unchanged.
-- @tparam number x vector X component
-- @tparam number y vector Y component
-- @tparam number z vector Z component
-- @tparam number maximum_length maximum vector length
-- @treturn number limited vector X component
-- @treturn number limited vector Y component
-- @treturn number limited vector Z component
function vector.limit_length(x, y, z, maximum_length)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)
  assertions.is_number(maximum_length)

  local length = vector.length(x, y, z)
  if length <= math.max(maximum_length, _MIN_LENGTH) then
    return x, y, z
  end

  local scale = maximum_length / length
  return x * scale, y * scale, z * scale
end

return vector
