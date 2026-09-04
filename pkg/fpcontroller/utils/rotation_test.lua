local luaunit = require("luaunit")
local rotation = require("pkg.fpcontroller.utils.rotation")

local function _assert_vector_equals(
  actual_x, actual_y, actual_z,
  expected_x, expected_y, expected_z
)
  luaunit.assert_almost_equals(actual_x, expected_x, 1e-9)
  luaunit.assert_almost_equals(actual_y, expected_y, 1e-9)
  luaunit.assert_almost_equals(actual_z, expected_z, 1e-9)
end

local function _assert_rotated_vector(orientation, x, y, z, expected_x, expected_y, expected_z)
  local actual_x, actual_y, actual_z = rotation.rotate_vector(orientation, x, y, z)
  _assert_vector_equals(actual_x, actual_y, actual_z, expected_x, expected_y, expected_z)
end

local function _assert_camera_direction(direction_x, direction_y, direction_z)
  local orientation = rotation.from_camera_direction(direction_x, direction_y, direction_z)
  local actual_x, actual_y, actual_z = rotation.to_camera_direction(orientation)
  local direction_length =
    math.sqrt(direction_x * direction_x + direction_y * direction_y + direction_z * direction_z)

  _assert_vector_equals(
    actual_x, actual_y, actual_z,
    direction_x / direction_length,
    direction_y / direction_length,
    direction_z / direction_length
  )
end

-- luacheck: globals TestRotation
TestRotation = {}

function TestRotation.test_from_angle_and_axis_rotates_around_normalized_axis()
  local orientation = rotation.from_angle_and_axis(math.pi, 0, 2, 0)

  _assert_rotated_vector(orientation, 0, 0, -1, 0, 0, 1)
end

function TestRotation.test_from_angle_and_axis_returns_identity_for_zero_rotation()
  local orientation = rotation.from_angle_and_axis(0, 0, 0, 0)

  luaunit.assert_equals(orientation, {1, 0, 0, 0})
end

function TestRotation.test_from_camera_direction_faces_cardinal_directions()
  _assert_camera_direction(0, 0, -1)
  _assert_camera_direction(1, 0, 0)
  _assert_camera_direction(0, 0, 1)
  _assert_camera_direction(-1, 0, 0)
end

function TestRotation.test_from_camera_direction_faces_diagonal_direction()
  _assert_camera_direction(1, 1, 1)
  _assert_camera_direction(-1, -1, 1)
end

function TestRotation.test_from_camera_direction_rejects_zero_direction()
  luaunit.assert_error_msg_contains(
    "camera direction must be nonzero",
    function()
      rotation.from_camera_direction(0, 0, 0)
    end
  )
end

function TestRotation.test_to_camera_direction()
  local orientation = rotation.from_angle_and_axis(math.pi / 2, 0, 1, 0)
  local direction_x, direction_y, direction_z = rotation.to_camera_direction(orientation)

  _assert_vector_equals(direction_x, direction_y, direction_z, -1, 0, 0)
end

function TestRotation.test_multiply()
  local first = rotation.from_angle_and_axis(math.pi / 2, 0, 1, 0)
  local second = rotation.from_angle_and_axis(math.pi / 2, 1, 0, 0)
  local product = rotation.multiply(first, second)

  local intermediate_x, intermediate_y, intermediate_z =
    rotation.rotate_vector(second, 0, 0, -1)
  local expected_x, expected_y, expected_z =
    rotation.rotate_vector(first, intermediate_x, intermediate_y, intermediate_z)

  _assert_rotated_vector(product, 0, 0, -1, expected_x, expected_y, expected_z)
end

function TestRotation.test_inverse()
  local orientation = rotation.from_angle_and_axis(0.7, 1, 2, 3)
  local inverted_orientation = rotation.inverse(orientation)

  local identity = rotation.multiply(orientation, inverted_orientation)

  _assert_rotated_vector(identity, 2, -1, 4, 2, -1, 4)
end

function TestRotation.test_difference()
  local from = rotation.from_angle_and_axis(math.pi / 3, 1, 0, 0)
  local to = rotation.from_angle_and_axis(math.pi / 2, 0, 1, 0)
  local difference = rotation.difference(from, to)

  local reconstructed = rotation.multiply(difference, from)
  local expected_x, expected_y, expected_z = rotation.rotate_vector(to, 1, 2, 3)

  _assert_rotated_vector(reconstructed, 1, 2, 3, expected_x, expected_y, expected_z)
end

function TestRotation.test_to_angle_axis()
  local orientation = rotation.from_angle_and_axis(3 * math.pi / 2, 0, 0, 1)
  local angle, axis_x, axis_y, axis_z = rotation.to_angle_axis(orientation)

  luaunit.assert_almost_equals(angle, math.pi / 2, 1e-9)
  _assert_vector_equals(axis_x, axis_y, axis_z, 0, 0, -1)
end

function TestRotation.test_to_rotation_vector()
  local orientation = rotation.from_angle_and_axis(math.pi / 3, 0, 2, 0)
  local x, y, z = rotation.to_rotation_vector(orientation)

  _assert_vector_equals(x, y, z, 0, math.pi / 3, 0)
end

function TestRotation.test_rotate_vector()
  local orientation = rotation.from_angle_and_axis(math.pi / 2, 0, 0, 1)

  _assert_rotated_vector(orientation, 2, 0, 0, 0, 2, 0)
end
