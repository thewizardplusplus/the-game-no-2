---
-- Quaternion helpers used by the physics controllers.
--
-- Quaternions are plain `{w, x, y, z}` tables. The module implements only the operations
-- needed by the first-person controller package and has no dependency on the LÖVR runtime.
--
-- @module rotation

local assertions = require("luatypechecks.assertions")
local vector = require("pkg.fpcontroller.utils.vector")

local _MIN_LENGTH = 1e-9

local function _atan2(y, x)
  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 then
    return math.atan(y / x) + (y >= 0 and math.pi or -math.pi)
  elseif y > 0 then
    return math.pi / 2
  elseif y < 0 then
    return -math.pi / 2
  end

  return 0
end

local function _normalized(w, x, y, z)
  local length = math.sqrt(w * w + x * x + y * y + z * z)
  if length <= _MIN_LENGTH then
    return {1, 0, 0, 0}
  end

  return {w / length, x / length, y / length, z / length}
end

local rotation = {}

---
-- ⚠️. Create a unit quaternion from an angle and an axis.
-- A zero angle or axis produces the identity rotation.
-- @tparam number angle rotation angle, in radians
-- @tparam number axis_x rotation axis X component
-- @tparam number axis_y rotation axis Y component
-- @tparam number axis_z rotation axis Z component
-- @treturn table unit quaternion
function rotation.from_angle_and_axis(angle, axis_x, axis_y, axis_z)
  assertions.is_number(angle)
  assertions.is_number(axis_x)
  assertions.is_number(axis_y)
  assertions.is_number(axis_z)

  local axis_length = vector.length(axis_x, axis_y, axis_z)
  if math.abs(angle) <= _MIN_LENGTH or axis_length <= _MIN_LENGTH then
    return {1, 0, 0, 0}
  end

  local half_angle = angle / 2
  local scale = math.sin(half_angle) / axis_length
  return _normalized(math.cos(half_angle), axis_x * scale, axis_y * scale, axis_z * scale)
end

---
-- ⚠️. Create a camera orientation whose forward axis points in a world-space direction.
-- The resulting orientation has no roll.
-- @tparam number direction_x direction X component
-- @tparam number direction_y direction Y component
-- @tparam number direction_z direction Z component
-- @treturn table unit quaternion
-- @raise if the direction is too small to normalize
function rotation.from_camera_direction(direction_x, direction_y, direction_z)
  assertions.is_number(direction_x)
  assertions.is_number(direction_y)
  assertions.is_number(direction_z)

  local length = vector.length(direction_x, direction_y, direction_z)
  if length <= _MIN_LENGTH then
    error("camera direction must be nonzero")
  end

  direction_x, direction_y, direction_z =
    direction_x / length, direction_y / length, direction_z / length

  local yaw = -_atan2(direction_x, -direction_z)
  local yaw_rotation = rotation.from_angle_and_axis(yaw, 0, 1, 0)

  local pitch = math.asin(math.max(-1, math.min(1, direction_y)))
  local pitch_rotation = rotation.from_angle_and_axis(pitch, 1, 0, 0)

  return rotation.multiply(yaw_rotation, pitch_rotation)
end

---
-- ⚠️. Return the world-space camera direction represented by an orientation.
-- Cameras face along their local negative Z axis.
-- @tparam table orientation unit quaternion
-- @treturn number normalized direction X component
-- @treturn number normalized direction Y component
-- @treturn number normalized direction Z component
function rotation.to_camera_direction(orientation)
  assertions.is_table(orientation)

  return rotation.rotate_vector(orientation, 0, 0, -1)
end

---
-- ⚠️. Multiply two quaternions and normalize the result.
-- When used to rotate a vector, `second` is applied before `first`.
-- @tparam table first left quaternion
-- @tparam table second right quaternion
-- @treturn table unit quaternion product
function rotation.multiply(first, second)
  assertions.is_table(first)
  assertions.is_table(second)

  local aw, ax, ay, az = first[1], first[2], first[3], first[4]
  local bw, bx, by, bz = second[1], second[2], second[3], second[4]
  return _normalized(
    aw * bw - ax * bx - ay * by - az * bz,
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw
  )
end

---
-- ⚠️. Return the inverse of a quaternion as a unit quaternion.
-- @tparam table value quaternion to invert
-- @treturn table inverse unit quaternion
function rotation.inverse(value)
  assertions.is_table(value)

  return _normalized(value[1], -value[2], -value[3], -value[4])
end

---
-- ⚠️. Return the world-space rotation that transforms `from` into `to`.
-- @tparam table from source unit quaternion
-- @tparam table to target unit quaternion
-- @treturn table difference unit quaternion
function rotation.difference(from, to)
  assertions.is_table(from)
  assertions.is_table(to)

  return rotation.multiply(to, rotation.inverse(from))
end

---
-- ⚠️. Convert a quaternion to the shortest angle-axis representation.
-- @tparam table value quaternion to convert
-- @treturn number rotation angle in the range from zero to pi, in radians
-- @treturn number rotation axis X component
-- @treturn number rotation axis Y component
-- @treturn number rotation axis Z component
function rotation.to_angle_axis(value)
  assertions.is_table(value)

  local normalized = _normalized(value[1], value[2], value[3], value[4])
  if normalized[1] < 0 then
    normalized = {-normalized[1], -normalized[2], -normalized[3], -normalized[4]}
  end

  local w = math.max(-1, math.min(1, normalized[1]))
  local angle = 2 * math.acos(w)
  local vector_length = math.sqrt(math.max(0, 1 - w * w))
  if vector_length <= _MIN_LENGTH then
    return 0, 0, 1, 0
  end

  return angle,
    normalized[2] / vector_length,
    normalized[3] / vector_length,
    normalized[4] / vector_length
end

---
-- ⚠️. Convert a quaternion to a shortest-path rotation vector.
-- The vector direction is the rotation axis and its length is the angle in radians.
-- @tparam table value quaternion to convert
-- @treturn number rotation vector X component
-- @treturn number rotation vector Y component
-- @treturn number rotation vector Z component
function rotation.to_rotation_vector(value)
  assertions.is_table(value)

  local angle, axis_x, axis_y, axis_z = rotation.to_angle_axis(value)
  return axis_x * angle, axis_y * angle, axis_z * angle
end

---
-- ⚠️. Rotate a vector by a unit quaternion.
-- @tparam table value unit quaternion
-- @tparam number x vector X component
-- @tparam number y vector Y component
-- @tparam number z vector Z component
-- @treturn number rotated vector X component
-- @treturn number rotated vector Y component
-- @treturn number rotated vector Z component
function rotation.rotate_vector(value, x, y, z)
  assertions.is_table(value)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  local w, qx, qy, qz = value[1], value[2], value[3], value[4]
  local tx, ty, tz = 2 * (qy * z - qz * y), 2 * (qz * x - qx * z), 2 * (qx * y - qy * x)
  return
    x + w * tx + qy * tz - qz * ty,
    y + w * ty + qz * tx - qx * tz,
    z + w * tz + qx * ty - qy * tx
end

return rotation
