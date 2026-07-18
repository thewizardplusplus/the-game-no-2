local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")

local CAMERA_ROTATION_SPEED = 0.625
local CAMERA_ORBIT_RADIUS = 1.5
local CAMERA_HEIGHT = 1
local CUBE_SIZE = 0.5

local skybox_texture = nil -- Texture
local cube_material = nil -- Material
local floor_material = nil -- Material
local camera_angle = 0

function lovr.load()
  skybox_texture = lovr.graphics.newTexture("resources/textures/skybox/skybox.png")

  local cube_texture = lovr.graphics.newTexture("resources/textures/cube/cube.png")
  cube_material = lovr.graphics.newMaterial({ texture = cube_texture })

  local floor_texture = lovr.graphics.newTexture("resources/textures/floor/floor.png")
  floor_material = lovr.graphics.newMaterial({ texture = floor_texture, uvScale = {5, 5} })
end

function lovr.draw(pass)
  assertions.is_true(type(pass) == "userdata")

  local camera_x = math.sin(camera_angle) * CAMERA_ORBIT_RADIUS
  local camera_z = math.cos(camera_angle) * CAMERA_ORBIT_RADIUS
  local camera_view = lovr.math.newMat4()
    :lookAt({camera_x, CAMERA_HEIGHT, camera_z}, {0, CUBE_SIZE / 2, 0})
  pass:setViewPose(1, camera_view, true)

  pass:skybox(skybox_texture)

  pass:setMaterial(floor_material)
  pass:plane(0, 0, 0, 5, 5, -math.pi / 2, 1, 0, 0, "fill")

  pass:setMaterial(cube_material)
  pass:cube(0, CUBE_SIZE / 2, 0, CUBE_SIZE, 0, 0, 1, 0, "fill")
end

function lovr.update(dt)
  assertions.is_number(dt)

  camera_angle = camera_angle + CAMERA_ROTATION_SPEED * dt
  if camera_angle > 2 * math.pi then
    camera_angle = camera_angle - 2 * math.pi
  end
end

function lovr.keypressed(key)
  assertions.is_string(key)

  if key == "escape" then
    lovr.event.quit()
  end
end
