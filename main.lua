local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")

local CUBE_ROTATION_SPEED = 1

local skybox_texture = nil -- Texture
local cube_material = nil -- Material
local cube_angle = 0

function lovr.load()
  skybox_texture = lovr.graphics.newTexture("resources/textures/skybox/skybox.png")

  local cube_texture = lovr.graphics.newTexture("resources/textures/cube/cube.png")
  cube_material = lovr.graphics.newMaterial({ texture = cube_texture })
end

function lovr.draw(pass)
  assertions.is_true(type(pass) == "userdata")

  pass:skybox(skybox_texture)

  pass:setMaterial(cube_material)
  pass:cube(0, 1.7, -1, 0.5, cube_angle, 0, 1, 0, "fill")
end

function lovr.update(dt)
  assertions.is_number(dt)

  cube_angle = cube_angle + CUBE_ROTATION_SPEED * dt
  if cube_angle > 2 * math.pi then
    cube_angle = cube_angle - 2 * math.pi
  end
end

function lovr.keypressed(key)
  assertions.is_string(key)

  if key == "escape" then
    lovr.event.quit()
  end
end
