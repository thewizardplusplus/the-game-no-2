local luaunit = require("luaunit")
local Wall = require("models.wall")

-- luacheck: globals TestWall
TestWall = {}

function TestWall.test_new_left()
  local wall = Wall:new(1, 2, 3, 4, 5, 0.1, "left", "room")

  luaunit.assert_equals(wall.x, 1)
  luaunit.assert_equals(wall.center_y, 4.5)
  luaunit.assert_equals(wall.z, 3)
  luaunit.assert_equals(wall.width, 4)
  luaunit.assert_equals(wall.height, 5)
  luaunit.assert_equals(wall.thickness, 0.1)
  luaunit.assert_equals(wall.angle, math.pi / 2)
  luaunit.assert_equals(wall.box_width, 0.1)
  luaunit.assert_equals(wall.box_depth, 4)
  luaunit.assert_equals(wall.surface_kind, "room")
end

function TestWall.test_new_right()
  local wall = Wall:new(1, 2, 3, 4, 5, 0.1, "right", "room")

  luaunit.assert_equals(wall.x, 1)
  luaunit.assert_equals(wall.center_y, 4.5)
  luaunit.assert_equals(wall.z, 3)
  luaunit.assert_equals(wall.width, 4)
  luaunit.assert_equals(wall.height, 5)
  luaunit.assert_equals(wall.thickness, 0.1)
  luaunit.assert_equals(wall.angle, -math.pi / 2)
  luaunit.assert_equals(wall.box_width, 0.1)
  luaunit.assert_equals(wall.box_depth, 4)
  luaunit.assert_equals(wall.surface_kind, "room")
end

function TestWall.test_new_front()
  local wall = Wall:new(1, 2, 3, 4, 5, 0.1, "front", "room")

  luaunit.assert_equals(wall.x, 1)
  luaunit.assert_equals(wall.center_y, 4.5)
  luaunit.assert_equals(wall.z, 3)
  luaunit.assert_equals(wall.width, 4)
  luaunit.assert_equals(wall.height, 5)
  luaunit.assert_equals(wall.thickness, 0.1)
  luaunit.assert_equals(wall.angle, 0)
  luaunit.assert_equals(wall.box_width, 4)
  luaunit.assert_equals(wall.box_depth, 0.1)
  luaunit.assert_equals(wall.surface_kind, "room")
end
