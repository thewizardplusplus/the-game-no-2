local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local colliderutils = require("pkg.fpcontroller.utils.collider")

-- MockCollider

local MockCollider = middleclass("ColliderMockCollider")

function MockCollider:initialize()
  self.position = vector(4, 5, 6)
  self.center = vector(1, 2, 3)
  self.orientation = quaternion.angleaxis(math.pi / 2, 0, 1, 0)
end

-- MockCollider / Motion

function MockCollider:getOrientation()
  return self.orientation:toangleaxis()
end

function MockCollider:getWorldPoint(point)
  assertions.is_table(point)

  return (self.position + point):unpack()
end

-- MockCollider / Mass

function MockCollider:getCenterOfMass()
  return self.center:unpack()
end

-- luacheck: globals TestColliderUtils
TestColliderUtils = {}

function TestColliderUtils.test_get_center_of_mass()
  local collider = MockCollider:new()

  luaunit.assert_equals(colliderutils.get_center_of_mass(collider), vector(5, 7, 9))
end

function TestColliderUtils.test_get_orientation()
  local collider = MockCollider:new()
  local orientation = colliderutils.get_orientation(collider)

  local direction_x, direction_y, direction_z = orientation:direction():unpack()

  luaunit.assert_almost_equals(direction_x, -1, 1e-9)
  luaunit.assert_almost_equals(direction_y, 0, 1e-9)
  luaunit.assert_almost_equals(direction_z, 0, 1e-9)
end
