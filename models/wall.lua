---
-- @classmod Wall

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")

local _WALL_ORIENTATIONS = {
  left = quaternion.angleaxis(math.pi / 2, 0, 1, 0),
  right = quaternion.angleaxis(-math.pi / 2, 0, 1, 0),
  front = quaternion.identity,
}

---
-- @table instance
-- @tfield vector position center position
-- @tfield vector size visible width, height, and collider thickness
-- @tfield quaternion orientation wall orientation
-- @tfield "room"|"stair" surface_kind

local Wall = middleclass("Wall")

---
-- @function new
-- @tparam vector bottom_position bottom-center position
-- @tparam vector size visible width, height, and collider thickness
-- @tparam "left"|"right"|"front" direction
-- @tparam "room"|"stair" surface_kind
-- @treturn Wall
function Wall:initialize(bottom_position, size, direction, surface_kind)
  assertions.is_table(bottom_position)
  assertions.is_table(size)
  assertions.is_enumeration(direction, {"left", "right", "front"})
  assertions.is_enumeration(surface_kind, {"room", "stair"})

  self.position = bottom_position + vector(0, size.y / 2, 0)
  self.size = size
  self.orientation = _WALL_ORIENTATIONS[direction]
  self.surface_kind = surface_kind
end

return Wall
