local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")

local CAMERA_ROTATION_SPEED = 0.625
local CAMERA_ORBIT_RADIUS = 2
local CAMERA_HEIGHT = 1.5
local FLOOR_SIZE = 5
local FLOOR_THICKNESS = 0.1
local CUBE_SIZE = 0.5
local CUBE_SPAWN_HEIGHT = 2
local CUBE_SPAWN_AREA_SIZE = 1.5
local CUBE_SPAWN_INTERVAL = 0.375
local MAX_CUBE_COUNT = 20

local skybox_texture = nil -- Texture
local cube_material = nil -- Material
local floor_material = nil -- Material
local camera_angle = 0
local physics_world = nil -- World
local cube_colliders = {} -- {Collider,...}
local cube_spawn_timer = 0

local function _set_random_orientation(collider)
  assertions.is_true(type(collider) == "userdata")

  local x_angle = 2 * math.pi * lovr.math.random()
  local y_angle = 2 * math.pi * lovr.math.random()
  local z_angle = 2 * math.pi * lovr.math.random()
  collider:setOrientation(quaternion.euler(x_angle, y_angle, z_angle))
end

local function _spawn_cube()
  if #cube_colliders >= MAX_CUBE_COUNT then
    local oldest_cube_collider = table.remove(cube_colliders, 1)
    oldest_cube_collider:destroy()
  end

  local half_spawn_area_size = CUBE_SPAWN_AREA_SIZE / 2
  local cube_x = (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_z = (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_collider = physics_world:newBoxCollider(
    cube_x, CUBE_SPAWN_HEIGHT, cube_z,
    CUBE_SIZE, CUBE_SIZE, CUBE_SIZE
  )
  _set_random_orientation(cube_collider)
  table.insert(cube_colliders, cube_collider)
end

function lovr.load()
  skybox_texture = lovr.graphics.newTexture("resources/textures/skybox/skybox.png")

  local cube_texture = lovr.graphics.newTexture("resources/textures/cube/cube.png")
  cube_material = lovr.graphics.newMaterial({ texture = cube_texture })

  local floor_texture = lovr.graphics.newTexture("resources/textures/floor/floor.png")
  floor_material = lovr.graphics.newMaterial({ texture = floor_texture, uvScale = {5, 5} })

  physics_world = lovr.physics.newWorld()

  local floor_collider = physics_world:newBoxCollider(
    0, -FLOOR_THICKNESS / 2, 0,
    FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE
  )
  floor_collider:setKinematic(true)

  _spawn_cube()
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
  pass:plane(0, 0, 0, FLOOR_SIZE, FLOOR_SIZE, -math.pi / 2, 1, 0, 0, "fill")

  pass:setMaterial(cube_material)
  for _, cube_collider in ipairs(cube_colliders) do
    local cube_x, cube_y, cube_z = cube_collider:getPosition()
    local cube_angle, cube_ax, cube_ay, cube_az = cube_collider:getOrientation()
    pass:cube(
      cube_x, cube_y, cube_z, CUBE_SIZE,
      cube_angle, cube_ax, cube_ay, cube_az,
      "fill"
    )
  end
end

function lovr.update(dt)
  assertions.is_number(dt)

  physics_world:update(dt)

  camera_angle = camera_angle + CAMERA_ROTATION_SPEED * dt
  if camera_angle > 2 * math.pi then
    camera_angle = camera_angle - 2 * math.pi
  end

  cube_spawn_timer = cube_spawn_timer + dt
  if cube_spawn_timer >= CUBE_SPAWN_INTERVAL then
    _spawn_cube()
    cube_spawn_timer = cube_spawn_timer - CUBE_SPAWN_INTERVAL
  end
end

function lovr.keypressed(key)
  assertions.is_string(key)

  if key == "escape" then
    lovr.event.quit()
  end
end
