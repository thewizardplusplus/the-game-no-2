---
-- @classmod FloorSection

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

---
-- @table instance
-- @tfield number x
-- @tfield number top_y
-- @tfield number z
-- @tfield number width
-- @tfield number thickness
-- @tfield number depth
-- @tfield "room"|"stair" surface_kind

local FloorSection = middleclass("FloorSection")

---
-- @function new
-- @tparam number x
-- @tparam number top_y
-- @tparam number z
-- @tparam number width
-- @tparam number thickness
-- @tparam number depth
-- @tparam "room"|"stair" surface_kind
-- @treturn FloorSection
function FloorSection:initialize(x, top_y, z, width, thickness, depth, surface_kind)
  assertions.is_number(x)
  assertions.is_number(top_y)
  assertions.is_number(z)
  assertions.is_number(width)
  assertions.is_number(thickness)
  assertions.is_number(depth)
  assertions.is_enumeration(surface_kind, {"room", "stair"})

  self.x, self.top_y, self.z = x, top_y, z
  self.width, self.thickness, self.depth = width, thickness, depth
  self.surface_kind = surface_kind
end

return FloorSection
