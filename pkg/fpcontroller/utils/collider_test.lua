local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local collider_utils = require("pkg.fpcontroller.utils.collider")
local rotation = require("pkg.fpcontroller.utils.rotation")

-- MockCollider

local MockCollider = middleclass("ColliderMockCollider")

function MockCollider:initialize()
  self.x, self.y, self.z = 4, 5, 6
  self.center_x, self.center_y, self.center_z = 1, 2, 3
  self.angle, self.axis_x, self.axis_y, self.axis_z = math.pi / 2, 0, 1, 0
end

-- MockCollider / Motion

function MockCollider:getOrientation()
  return self.angle, self.axis_x, self.axis_y, self.axis_z
end

function MockCollider:getWorldPoint(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  return self.x + x, self.y + y, self.z + z
end

-- MockCollider / Mass

function MockCollider:getCenterOfMass()
  return self.center_x, self.center_y, self.center_z
end

-- luacheck: globals TestColliderUtils
TestColliderUtils = {}

function TestColliderUtils.test_get_center_of_mass()
  local collider = MockCollider:new()

  luaunit.assert_equals({collider_utils.get_center_of_mass(collider)}, {5, 7, 9})
end

function TestColliderUtils.test_get_orientation()
  local collider = MockCollider:new()
  local orientation = collider_utils.get_orientation(collider)

  local direction_x, direction_y, direction_z = rotation.to_camera_direction(orientation)

  luaunit.assert_almost_equals(direction_x, -1, 1e-9)
  luaunit.assert_almost_equals(direction_y, 0, 1e-9)
  luaunit.assert_almost_equals(direction_z, 0, 1e-9)
end
