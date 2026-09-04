local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
package.path = table.concat(require_paths, ";")

local luaunit = require("luaunit")

for _, module in ipairs({
  "models.floorsection",
  "models.room",
  "models.wall",
  "pkg.fpcontroller.utils.init",
  "pkg.fpcontroller.utils.vector",
  "pkg.fpcontroller.utils.rotation",
  "pkg.fpcontroller.utils.collider",
  "pkg.fpcontroller.fpcontroller",
  "pkg.fpcontroller.posecontroller",
  "pkg.fpcontroller.carrycontroller",
}) do
  require(module .. "_test")
end

os.exit(luaunit.run())
