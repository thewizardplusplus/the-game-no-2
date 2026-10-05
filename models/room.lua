---
-- @classmod Room

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

---
-- @table instance
-- @tfield vector floor_position floor-center position
-- @tfield "positive"|"negative" open_side

local Room = middleclass("Room")

---
-- @function new
-- @tparam vector floor_position floor-center position
-- @tparam "positive"|"negative" open_side
-- @treturn Room
function Room:initialize(floor_position, open_side)
  assertions.is_table(floor_position)
  assertions.is_enumeration(open_side, {"positive", "negative"})

  self.floor_position = floor_position
  self.open_side = open_side
end

return Room
