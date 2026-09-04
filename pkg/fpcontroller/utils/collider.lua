---
-- LÖVR Collider adapters used by the physics controllers.
--
-- @module collider

local assertions = require("luatypechecks.assertions")
local checks = require("luatypechecks.checks")
local rotation = require("pkg.fpcontroller.utils.rotation")

local collider_utils = {}

---
-- ⚠️. Return a collider's center of mass in world coordinates.
-- @tparam Collider value collider to query
-- @treturn number world X coordinate
-- @treturn number world Y coordinate
-- @treturn number world Z coordinate
function collider_utils.get_center_of_mass(value)
  assertions.is_true(type(value) == "userdata" or checks.is_table(value))

  local center_x, center_y, center_z = value:getCenterOfMass()
  return value:getWorldPoint(center_x, center_y, center_z)
end

---
-- ⚠️. Return a collider's world orientation as a unit quaternion.
-- @tparam Collider value collider to query
-- @treturn table unit quaternion
function collider_utils.get_orientation(value)
  assertions.is_true(type(value) == "userdata" or checks.is_table(value))

  return rotation.from_angle_and_axis(value:getOrientation())
end

return collider_utils
