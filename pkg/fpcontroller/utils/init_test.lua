local luaunit = require("luaunit")
local utils = require("pkg.fpcontroller.utils")

-- luacheck: globals TestFPControllerUtils
TestFPControllerUtils = {}

function TestFPControllerUtils.test_shallow_copy()
  local nested = { value = 2 }
  local original = { value = 1, nested = nested }

  local copy = utils.shallow_copy(original)

  luaunit.assert_not_is(copy, original)
  luaunit.assert_equals(copy, original)
  luaunit.assert_is(copy.nested, nested)

  copy.value = 3
  luaunit.assert_equals(original.value, 1)

  copy.nested.value = 4
  luaunit.assert_equals(original.nested.value, 4)
end
