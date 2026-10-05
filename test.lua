local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
package.path = table.concat(require_paths, ";")

local tests = require("constants.tests")

local test_command = string.format("%s=TRUE lovr test.lua", tests.TEST_ENVIRONMENT_VARIABLE)
assert(
  os.getenv(tests.TEST_ENVIRONMENT_VARIABLE) ~= nil,
  string.format("tests must be run in headless mode: %s", test_command)
)
assert(
  vector and quaternion,
  string.format("tests must be run with LÖVR 0.19 or newer: %s", test_command)
)
for module_name, is_enabled in pairs(tests.TEST_MODULES) do
  if is_enabled then
    assert(
      lovr[module_name] ~= nil,
      string.format("the %q module must be enabled for tests", module_name)
    )
  end
end

local luaunit = require("luaunit")

for _, module in ipairs({
  "models.floorsection",
  "models.room",
  "models.wall",
  "pkg.fpcontroller.utils.init",
  "pkg.fpcontroller.utils.vector",
  "pkg.fpcontroller.utils.quaternion",
  "pkg.fpcontroller.utils.collider",
  "pkg.fpcontroller.fpcontroller",
  "pkg.fpcontroller.posecontroller",
  "pkg.fpcontroller.carrycontroller",
}) do
  require(module .. "_test")
end

os.exit(luaunit.run())
