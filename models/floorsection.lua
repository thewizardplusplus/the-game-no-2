---
-- @classmod FloorSection

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

---
-- @table instance
-- @tfield vector position top-center position
-- @tfield vector size width, thickness, and depth
-- @tfield "room"|"stair" surface_kind

local FloorSection = middleclass("FloorSection")

---
-- @function new
-- @tparam vector position top-center position
-- @tparam vector size width, thickness, and depth
-- @tparam "room"|"stair" surface_kind
-- @treturn FloorSection
function FloorSection:initialize(position, size, surface_kind)
  assertions.is_table(position)
  assertions.is_table(size)
  assertions.is_enumeration(surface_kind, {"room", "stair"})

  self.position = position
  self.size = size
  self.surface_kind = surface_kind
end

return FloorSection
