local luaunit = require("luaunit")
local FloorSection = require("models.floorsection")

-- luacheck: globals TestFloorSection
TestFloorSection = {}

function TestFloorSection.test_new()
  local section = FloorSection:new(vector(1, 2, 3), vector(4, 5, 6), "room")

  luaunit.assert_equals(section.position, vector(1, 2, 3))
  luaunit.assert_equals(section.size, vector(4, 5, 6))
  luaunit.assert_equals(section.surface_kind, "room")
end
