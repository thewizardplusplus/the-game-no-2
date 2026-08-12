local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")

local function _set_title(config, title)
  assertions.is_table(config)
  assertions.is_string(title)

  config.window.title = title
  config.identity = string.lower(title)
end

local function _set_screen_width(config, width, aspect_ratio)
  assertions.is_table(config)
  assertions.is_number(width)
  assertions.is_number(aspect_ratio)

  config.window.width = width
  config.window.height = width / aspect_ratio
end

function lovr.conf(config)
  assertions.is_table(config)

  config.version = "0.19.0"

  -- this is a flatscreen game; the headset simulator otherwise owns the
  -- mouse mode and only captures it while the left button is held
  config.modules.headset = false
  config.window.resizable = true

  _set_title(config, "The Game No. 2")
  _set_screen_width(config, 640, 16 / 10)
end
