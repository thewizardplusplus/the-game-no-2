---
-- @module tests

local tests = {}

---
-- @table tests
-- @tfield string TEST_ENVIRONMENT_VARIABLE
-- @tfield {[string]=boolean,...} TEST_MODULES

tests.TEST_ENVIRONMENT_VARIABLE = "LOVR_HEADLESS_TEST"
tests.TEST_MODULES = { math = true }

return tests
