local luaunit = require("luaunit")
local Room = require("models.room")

-- luacheck: globals TestRoom
TestRoom = {}

function TestRoom.test_new()
  local room = Room:new(1, 2, "positive")

  luaunit.assert_equals(room.center_z, 1)
  luaunit.assert_equals(room.floor_height, 2)
  luaunit.assert_equals(room.open_side, "positive")
end
