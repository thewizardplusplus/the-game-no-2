---
-- Quaternion helpers used by the physics controllers.
--
-- @module quaternion

local assertions = require("luatypechecks.assertions")

local _MIN_ROTATION_ANGLE = 1e-6

local function _is_finite(value)
  local is_not_nan = value == value
  local is_not_infinite = math.abs(value) < math.huge
  return is_not_nan and is_not_infinite
end

local quaternionutils = {}

---
-- ⚠️. Return the world-space rotation that transforms `from` into `to`.
-- @tparam quaternion from source orientation
-- @tparam quaternion to target orientation
-- @treturn quaternion difference orientation
function quaternionutils.difference(from, to)
  assertions.is_table(from)
  assertions.is_table(to)

  return to * from:conjugate()
end

---
-- ⚠️. Convert a quaternion to a shortest-path rotation vector.
-- The vector direction is the rotation axis and its length is the angle in radians.
-- Identity and numerically invalid angle-axis representations produce a zero vector.
-- @tparam quaternion value quaternion to convert
-- @treturn vector rotation vector
function quaternionutils.to_rotation_vector(value)
  assertions.is_table(value)

  local angle, axis_x, axis_y, axis_z = value:toangleaxis()

  -- prevent invalid angle-axis values from propagating into physics calculations
  if
    not _is_finite(angle)
      or not _is_finite(axis_x)
      or not _is_finite(axis_y)
      or not _is_finite(axis_z)
  then
    return vector.zero
  end

  -- treat near-zero and near-full-turn rotations as identity because their axis is unstable
  if angle <= _MIN_ROTATION_ANGLE or 2 * math.pi - angle <= _MIN_ROTATION_ANGLE then
    return vector.zero
  end

  -- use the equivalent signed angle with the smallest magnitude
  if angle > math.pi then
    angle = angle - 2 * math.pi
  end

  return vector(axis_x, axis_y, axis_z) * angle
end

return quaternionutils
