local luaunit = require("luaunit")
local Room = require("models.room")

-- luacheck: globals TestRoom
TestRoom = {}

function TestRoom.test_new()
  local room = Room:new(vector(0, 2, 1), "positive")

  luaunit.assert_equals(room.floor_position, vector(0, 2, 1))
  luaunit.assert_equals(room.open_side, "positive")
end
