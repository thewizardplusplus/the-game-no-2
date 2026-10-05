local luaunit = require("luaunit")
local vectorutils = require("pkg.fpcontroller.utils.vector")

-- luacheck: globals TestVector
TestVector = {}

function TestVector.test_limit_length_scales_long_vector()
  local value = vector(2, -3, 6)
  local limited_value = vectorutils.limit_length(value, 3.5)

  luaunit.assert_almost_equals(limited_value.x, 1, 1e-9)
  luaunit.assert_almost_equals(limited_value.y, -1.5, 1e-9)
  luaunit.assert_almost_equals(limited_value.z, 3, 1e-9)
  luaunit.assert_equals(value, vector(2, -3, 6))
end

function TestVector.test_limit_length_preserves_short_vector()
  local value = vector(1, 2, 2)

  luaunit.assert_is(vectorutils.limit_length(value, 4), value)
end

function TestVector.test_limit_length_preserves_zero_vector()
  local value = vector.zero

  luaunit.assert_is(vectorutils.limit_length(value, 1), value)
end
