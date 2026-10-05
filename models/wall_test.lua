local luaunit = require("luaunit")
local Wall = require("models.wall")

-- luacheck: globals TestWall
TestWall = {}

function TestWall.test_new_left()
  local wall = Wall:new(vector(1, 2, 3), vector(4, 5, 0.1), "left", "room")

  luaunit.assert_equals(wall.position, vector(1, 4.5, 3))
  luaunit.assert_equals(wall.size, vector(4, 5, 0.1))
  luaunit.assert_equals(wall.orientation, quaternion.angleaxis(math.pi / 2, 0, 1, 0))
  luaunit.assert_equals(wall.surface_kind, "room")
end

function TestWall.test_new_right()
  local wall = Wall:new(vector(1, 2, 3), vector(4, 5, 0.1), "right", "room")

  luaunit.assert_equals(wall.position, vector(1, 4.5, 3))
  luaunit.assert_equals(wall.size, vector(4, 5, 0.1))
  luaunit.assert_equals(wall.orientation, quaternion.angleaxis(-math.pi / 2, 0, 1, 0))
  luaunit.assert_equals(wall.surface_kind, "room")
end

function TestWall.test_new_front()
  local wall = Wall:new(vector(1, 2, 3), vector(4, 5, 0.1), "front", "room")

  luaunit.assert_equals(wall.position, vector(1, 4.5, 3))
  luaunit.assert_equals(wall.size, vector(4, 5, 0.1))
  luaunit.assert_equals(wall.orientation, quaternion.identity)
  luaunit.assert_equals(wall.surface_kind, "room")
end
