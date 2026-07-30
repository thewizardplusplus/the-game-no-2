---
-- @classmod Wall

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

---
-- @table instance
-- @tfield number x
-- @tfield number center_y
-- @tfield number z
-- @tfield number width
-- @tfield number height
-- @tfield number thickness
-- @tfield number angle
-- @tfield number box_width
-- @tfield number box_depth
-- @tfield "room"|"stair" surface_kind

local Wall = middleclass("Wall")

---
-- @function new
-- @tparam number x
-- @tparam number bottom_y
-- @tparam number z
-- @tparam number width
-- @tparam number height
-- @tparam number thickness
-- @tparam "left"|"right"|"front" direction
-- @tparam "room"|"stair" surface_kind
-- @treturn Wall
function Wall:initialize(
  x, bottom_y, z,
  width, height, thickness,
  direction,
  surface_kind
)
  assertions.is_number(x)
  assertions.is_number(bottom_y)
  assertions.is_number(z)
  assertions.is_number(width)
  assertions.is_number(height)
  assertions.is_number(thickness)
  assertions.is_enumeration(direction, {"left", "right", "front"})
  assertions.is_enumeration(surface_kind, {"room", "stair"})

  local angle = nil
  local box_width, box_depth = nil, nil
  if direction == "left" then
    angle = math.pi / 2
    box_width, box_depth = thickness, width
  elseif direction == "right" then
    angle = -math.pi / 2
    box_width, box_depth = thickness, width
  elseif direction == "front" then
    angle = 0
    box_width, box_depth = width, thickness
  end

  self.x, self.center_y, self.z = x, bottom_y + height / 2, z
  self.width, self.height, self.thickness = width, height, thickness
  self.angle = angle
  self.box_width, self.box_depth = box_width, box_depth
  self.surface_kind = surface_kind
end

return Wall
