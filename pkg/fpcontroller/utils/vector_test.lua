local luaunit = require("luaunit")
local vector = require("pkg.fpcontroller.utils.vector")

-- luacheck: globals TestVector
TestVector = {}

function TestVector.test_length()
  luaunit.assert_equals(vector.length(2, -3, 6), 7)
end

function TestVector.test_limit_length_scales_long_vector()
  local x, y, z = vector.limit_length(2, -3, 6, 3.5)

  luaunit.assert_almost_equals(x, 1, 1e-9)
  luaunit.assert_almost_equals(y, -1.5, 1e-9)
  luaunit.assert_almost_equals(z, 3, 1e-9)
end

function TestVector.test_limit_length_preserves_short_vector()
  luaunit.assert_equals({vector.limit_length(1, 2, 2, 4)}, {1, 2, 2})
end

function TestVector.test_limit_length_preserves_zero_vector()
  luaunit.assert_equals({vector.limit_length(0, 0, 0, 1)}, {0, 0, 0})
end
