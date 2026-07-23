local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")
local BaseShading = require("lovr-base-shading")

local CAMERA_ROTATION_SPEED = 0.625
local CAMERA_ORBIT_RADIUS = 2
local CAMERA_HEIGHT = 1.5
local MOON_LIGHT_INDEX = 1
local MOON_SHADOW_SIZE = 5
local FLASHLIGHT_LIGHT_INDEX = 2
local FLASHLIGHT_WIDE_LIGHT_INDEX = 3
local FLASHLIGHT_FILL_LIGHT_INDEX = 4
local FLASHLIGHT_RIGHT_OFFSET = 0.25
local FLASHLIGHT_DOWN_OFFSET = 0.15
local FLOOR_SIZE = 5
local FLOOR_THICKNESS = 0.1
local CUBE_SIZE = 0.5
local CUBE_SPAWN_HEIGHT = 2
local CUBE_SPAWN_AREA_SIZE = 1.5
local CUBE_SPAWN_INTERVAL = 0.375
local MAX_LIGHT_COUNT = 8
local MAX_CUBE_COUNT = 20

local skybox_texture = nil -- Texture
local cube_material = nil -- Material
local cube_shading_material = nil -- BaseMaterial
local floor_material = nil -- Material
local floor_shading_material = nil -- BaseMaterial
local base_shading = nil -- BaseShading
local surface_shader = nil -- Shader
local ambient = nil -- Vec4
local lights = {} -- {BaseLight,...}
local is_flashlight_enabled = true
local shadow = BaseShading.newShadow() -- BaseShadow
local camera_angle = 0
local physics_world = nil -- World
local cube_colliders = {} -- {Collider,...}
local cube_spawn_timer = 0

local function _new_linear_color(red, green, blue)
  assertions.is_number(red)
  assertions.is_number(green)
  assertions.is_number(blue)

  red, green, blue = lovr.math.gammaToLinear(red, green, blue)
  return lovr.math.newVec4(red, green, blue, 1)
end

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
  cube_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.25, 0.25, 0.25, 1),
    diffuse = lovr.math.newVec4(0.8, 0.8, 0.8, 1),
    specular = lovr.math.newVec4(0.08, 0.08, 0.08, 1),
    shininess = 8,
  })

  local floor_texture = lovr.graphics.newTexture("resources/textures/floor/floor.png")
  floor_material = lovr.graphics.newMaterial({ texture = floor_texture, uvScale = {5, 5} })
  floor_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.3, 0.3, 0.3, 1),
    diffuse = lovr.math.newVec4(0.9, 0.9, 0.9, 1),
    specular = lovr.math.newVec4(0.45, 0.45, 0.45, 1),
    shininess = 48,
  })

  base_shading = BaseShading:new({ shadowResolution = 1024 })
  surface_shader = base_shading:newSurfaceShader()

  ambient = _new_linear_color(0.145, 0.19, 0.35)

  -- the library requires all light slots to be initialized at once,
  -- but new lights are inactive by default
  for _ = 1, MAX_LIGHT_COUNT do
    table.insert(lights, BaseShading.newLight())
  end

  local moon_direction = lovr.math.newVec3(0.321, 0.767, 0.555):normalize()
  local moon_x, moon_y, moon_z = moon_direction:unpack()
  lights[MOON_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[MOON_LIGHT_INDEX].position = lovr.math.newVec4(moon_x, moon_y, moon_z, 0)
  lights[MOON_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.494, 0.479)
  lights[MOON_LIGHT_INDEX].specular = _new_linear_color(0.5, 0.494, 0.479)

  lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_LIGHT_INDEX].spotCutoff = 35
  lights[FLASHLIGHT_LIGHT_INDEX].spotExponent = 2
  lights[FLASHLIGHT_LIGHT_INDEX].diffuse = lovr.math.newVec4(1, 1, 1, 1)
  lights[FLASHLIGHT_LIGHT_INDEX].specular = lovr.math.newVec4(1, 1, 1, 1)

  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotCutoff = 42.5
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotExponent = 2
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.5, 0.5)

  lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.46, 0.4)
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].linearAttenuation = 0.5
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].quadraticAttenuation = 0.5

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
  local camera_target_y = CUBE_SIZE / 2
  local camera_view = lovr.math.newMat4()
    :lookAt({camera_x, CAMERA_HEIGHT, camera_z}, {0, camera_target_y, 0})
  pass:setViewPose(1, camera_view, true)

  pass:skybox(skybox_texture)

  local camera_direction =
    lovr.math.newVec3(-camera_x, camera_target_y - CAMERA_HEIGHT, -camera_z):normalize()
  local camera_direction_x, _, camera_direction_z = camera_direction:unpack()
  local camera_right = lovr.math.newVec3(-camera_direction_z, 0, camera_direction_x):normalize()
  local camera_right_x, _, camera_right_z = camera_right:unpack()
  lights[FLASHLIGHT_LIGHT_INDEX].spotDirection = camera_direction
  lights[FLASHLIGHT_LIGHT_INDEX].position = lovr.math.newVec4(
    camera_x + camera_right_x * FLASHLIGHT_RIGHT_OFFSET,
    CAMERA_HEIGHT - FLASHLIGHT_DOWN_OFFSET,
    camera_z + camera_right_z * FLASHLIGHT_RIGHT_OFFSET,
    1
  )
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].position = lights[FLASHLIGHT_LIGHT_INDEX].position
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotDirection = lights[FLASHLIGHT_LIGHT_INDEX].spotDirection
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].position = lights[FLASHLIGHT_LIGHT_INDEX].position

  base_shading:resetShadowPass()
  if is_flashlight_enabled then
    lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    shadow.lightIndex = FLASHLIGHT_LIGHT_INDEX

    local flashlight_x, flashlight_y, flashlight_z =
      lights[FLASHLIGHT_LIGHT_INDEX].position:unpack()
    base_shading:sendSpotlightShadow(
      lovr.math.newVec3(flashlight_x, flashlight_y, flashlight_z),
      lights[FLASHLIGHT_LIGHT_INDEX].spotDirection,
      lights[FLASHLIGHT_LIGHT_INDEX].spotCutoff,
      0.1, -- near
      10 -- far
    )
  else
    lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    shadow.lightIndex = MOON_LIGHT_INDEX

    local moon_x, moon_y, moon_z = lights[MOON_LIGHT_INDEX].position:unpack()
    base_shading:sendDirectionalShadow(
      lovr.math.newVec3(
        moon_x * MOON_SHADOW_SIZE,
        moon_y * MOON_SHADOW_SIZE,
        moon_z * MOON_SHADOW_SIZE
      ),
      lovr.math.newVec3(-moon_x, -moon_y, -moon_z),
      MOON_SHADOW_SIZE,
      0.1, -- near
      10 -- far
    )
  end

  pass:setShader(surface_shader)
  base_shading:sendAmbient(pass, ambient)
  base_shading:sendLights(pass, lights)
  base_shading:sendShadow(pass, shadow)
  base_shading:sendFog(pass, BaseShading.noFog)

  pass:setMaterial(floor_material)
  base_shading:sendMaterial(pass, floor_shading_material)
  pass:plane(0, 0, 0, FLOOR_SIZE, FLOOR_SIZE, -math.pi / 2, 1, 0, 0, "fill")

  pass:setMaterial(cube_material)
  base_shading:sendMaterial(pass, cube_shading_material)
  for _, cube_collider in ipairs(cube_colliders) do
    local cube_x, cube_y, cube_z = cube_collider:getPosition()
    local cube_angle, cube_ax, cube_ay, cube_az = cube_collider:getOrientation()
    pass:cube(
      cube_x, cube_y, cube_z, CUBE_SIZE,
      cube_angle, cube_ax, cube_ay, cube_az,
      "fill"
    )
    base_shading.shadowPass:cube(
      cube_x, cube_y, cube_z, CUBE_SIZE,
      cube_angle, cube_ax, cube_ay, cube_az,
      "fill"
    )
  end

  return lovr.graphics.submit(base_shading.shadowPass, pass)
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

  if key == "f" then
    is_flashlight_enabled = not is_flashlight_enabled
  end

  if key == "f11" then
    local is_fullscreen = lovr.system.isWindowFullscreen()
    lovr.system.setWindowFullscreen(not is_fullscreen)
  end

  if key == "escape" then
    lovr.event.quit()
  end
end
