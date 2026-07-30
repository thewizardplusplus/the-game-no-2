local luaunit = require("luaunit")
local FloorSection = require("models.floorsection")

-- luacheck: globals TestFloorSection
TestFloorSection = {}

function TestFloorSection.test_new()
  local section = FloorSection:new(1, 2, 3, 4, 5, 6, "room")

  luaunit.assert_equals(section.x, 1)
  luaunit.assert_equals(section.top_y, 2)
  luaunit.assert_equals(section.z, 3)
  luaunit.assert_equals(section.width, 4)
  luaunit.assert_equals(section.thickness, 5)
  luaunit.assert_equals(section.depth, 6)
  luaunit.assert_equals(section.surface_kind, "room")
end
