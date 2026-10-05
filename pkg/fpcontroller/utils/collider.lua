---
-- LÖVR Collider adapters used by the physics controllers.
--
-- @module collider

local assertions = require("luatypechecks.assertions")
local checks = require("luatypechecks.checks")

local colliderutils = {}

---
-- ⚠️. Return a collider's center of mass in world coordinates.
-- @tparam Collider value collider to query
-- @treturn vector center of mass in world coordinates
function colliderutils.get_center_of_mass(value)
  assertions.is_true(type(value) == "userdata" or checks.is_table(value))

  local center = vector(value:getCenterOfMass())
  return vector(value:getWorldPoint(center))
end

---
-- ⚠️. Return a collider's world orientation as a unit quaternion.
-- @tparam Collider value collider to query
-- @treturn quaternion world orientation
function colliderutils.get_orientation(value)
  assertions.is_true(type(value) == "userdata" or checks.is_table(value))

  return quaternion.angleaxis(value:getOrientation())
end

return colliderutils
