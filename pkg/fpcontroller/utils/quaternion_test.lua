local luaunit = require("luaunit")
local quaternionutils = require("pkg.fpcontroller.utils.quaternion")

local function _assert_vector_almost_equals(actual, expected)
  luaunit.assert_almost_equals(actual.x, expected.x, 1e-9)
  luaunit.assert_almost_equals(actual.y, expected.y, 1e-9)
  luaunit.assert_almost_equals(actual.z, expected.z, 1e-9)
end

-- luacheck: globals TestQuaternion
TestQuaternion = {}

function TestQuaternion.test_difference()
  local from = quaternion.angleaxis(math.pi / 3, 1, 0, 0)
  local to = quaternion.angleaxis(math.pi / 2, 0, 1, 0)
  local difference = quaternionutils.difference(from, to)

  _assert_vector_almost_equals(
    difference * (from * vector(1, 2, 3)),
    to * vector(1, 2, 3)
  )
end

function TestQuaternion.test_to_rotation_vector()
  local orientation = quaternion.angleaxis(math.pi / 3, 0, 2, 0)

  _assert_vector_almost_equals(
    quaternionutils.to_rotation_vector(orientation),
    vector(0, math.pi / 3, 0)
  )
end

function TestQuaternion.test_to_rotation_vector_uses_shortest_path()
  local orientation = quaternion.angleaxis(3 * math.pi / 2, 0, 0, 1)

  _assert_vector_almost_equals(
    quaternionutils.to_rotation_vector(orientation),
    vector(0, 0, -math.pi / 2)
  )
end

function TestQuaternion.test_to_rotation_vector_handles_identity()
  luaunit.assert_equals(quaternionutils.to_rotation_vector(quaternion.identity), vector.zero)
end

function TestQuaternion.test_to_rotation_vector_handles_near_zero_angle()
  local orientation = quaternion.angleaxis(0.5e-6, 1, 0, 0)

  luaunit.assert_equals(quaternionutils.to_rotation_vector(orientation), vector.zero)
end

function TestQuaternion.test_to_rotation_vector_handles_near_full_turn()
  local orientation = quaternion.angleaxis(2 * math.pi - 0.5e-6, 1, 0, 0)

  luaunit.assert_equals(quaternionutils.to_rotation_vector(orientation), vector.zero)
end
