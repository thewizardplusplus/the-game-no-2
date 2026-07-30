---
-- @classmod Room

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

---
-- @table instance
-- @tfield number center_z
-- @tfield number floor_height
-- @tfield "positive"|"negative" open_side

local Room = middleclass("Room")

---
-- @function new
-- @tparam number center_z
-- @tparam number floor_height
-- @tparam "positive"|"negative" open_side
-- @treturn Room
function Room:initialize(center_z, floor_height, open_side)
  assertions.is_number(center_z)
  assertions.is_number(floor_height)
  assertions.is_enumeration(open_side, {"positive", "negative"})

  self.center_z = center_z
  self.floor_height = floor_height
  self.open_side = open_side
end

return Room
