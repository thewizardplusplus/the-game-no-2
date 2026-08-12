local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")
local BaseShading = require("lovr-base-shading")
local FloorSection = require("models.floorsection")
local Room = require("models.room")
local Wall = require("models.wall")
local FPController = require("pkg.fpcontroller")

local PLAYER_HEIGHT = 1.8
local PLAYER_START_BOTTOM_Y = 5
local PLAYER_START_Y = PLAYER_START_BOTTOM_Y + PLAYER_HEIGHT / 2
local PLAYER_SPEED = 1.7
local MOON_LIGHT_INDEX = 1
local MOON_SHADOW_DISTANCE = 15
local MOON_SHADOW_ORTHOGRAPHIC_SIZE = 7
local FLASHLIGHT_LIGHT_INDEX = 2
local FLASHLIGHT_WIDE_LIGHT_INDEX = 3
local FLASHLIGHT_FILL_LIGHT_INDEX = 4
local FLASHLIGHT_RIGHT_OFFSET = 0.25
local FLASHLIGHT_DOWN_OFFSET = 0.15
local FLOOR_SIZE = 5
local FLOOR_THICKNESS = 0.1
local FLOOR_PLANE_OFFSET = 0.001
local FLOOR_FRICTION = 0.2
local STAIR_LENGTH = FLOOR_SIZE / 2
local ROOM_DISTANCE = FLOOR_SIZE + STAIR_LENGTH
local LOWER_ROOM_Z = -ROOM_DISTANCE / 2
local UPPER_ROOM_Z = ROOM_DISTANCE / 2
local STAIR_STEP_COUNT = 5
local STAIR_STEP_DEPTH = STAIR_LENGTH / STAIR_STEP_COUNT
local STAIR_STEP_HEIGHT = 0.2
local UPPER_ROOM_HEIGHT = STAIR_STEP_COUNT * STAIR_STEP_HEIGHT
local WALL_HEIGHT = FLOOR_SIZE / 2
local WALL_COLLIDER_THICKNESS = 0.1
local WALL_FRICTION = 0.8
local CUBE_SIZE = 0.5
local CUBE_MASS = 20
local CUBE_FRICTION = 0.6
local CUBE_SPAWN_HEIGHT = UPPER_ROOM_HEIGHT + WALL_HEIGHT
local CUBE_SPAWN_AREA_SIZE = 1.5
local CUBE_SPAWN_INTERVAL = 0.375
local MAX_LIGHT_COUNT = 8
local MAX_CUBE_COUNT = 40

local is_fullscreen = true
local is_mouse_captured = false
local skybox_texture = nil -- Texture
local cube_material = nil -- Material
local cube_shading_material = nil -- BaseMaterial
local concrete_texture = nil -- Texture
local concrete_materials = {} -- {[string]=Material,...}
local concrete_shading_material = nil -- BaseMaterial
local floor_material = nil -- Material
local stair_floor_material = nil -- Material
local floor_shading_material = nil -- BaseMaterial
local wall_material = nil -- Material
local stair_wall_material = nil -- Material
local wall_shading_material = nil -- BaseMaterial
local base_shading = nil -- BaseShading
local surface_shader = nil -- Shader
local ambient = nil -- Vec4
local lights = {} -- {BaseLight,...}
local is_flashlight_enabled = true
local shadow = BaseShading.newShadow({ bias = 0.0001 }) -- BaseShadow
local physics_world = nil -- World
local player_controller = nil -- FPController
local cube_colliders = {} -- {Collider,...}
local cube_spawn_timer = 0
local floor_sections = {} -- {FloorSection,...}
local floor_section_materials = {} -- {Material,...}
local walls = {} -- {Wall,...}
local wall_materials = {} -- {Material,...}

local function _get_normalized_input()
  local input_x = (lovr.system.isKeyDown("d") and 1 or 0) - (lovr.system.isKeyDown("a") and 1 or 0)
  local input_z = (lovr.system.isKeyDown("s") and 1 or 0) - (lovr.system.isKeyDown("w") and 1 or 0)
  local input_length = math.sqrt(input_x * input_x + input_z * input_z)
  if input_length > 1 then
    input_x, input_z = input_x / input_length, input_z / input_length
  end

  return input_x, input_z
end

local function _set_mouse_captured(captured)
  assertions.is_boolean(captured)

  is_mouse_captured = captured
  lovr.system.setMouseMode(captured and "relative" or "normal")
end

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

local function _get_concrete_material(u_scale, v_scale)
  assertions.is_number(u_scale)
  assertions.is_number(v_scale)

  local key = string.format("%.10g:%.10g", u_scale, v_scale)
  if concrete_materials[key] == nil then
    concrete_materials[key] = lovr.graphics.newMaterial({
      texture = concrete_texture,
      uvScale = {u_scale, v_scale},
    })
  end

  return concrete_materials[key]
end

local function _spawn_cube()
  if #cube_colliders >= MAX_CUBE_COUNT then
    local oldest_cube_collider = table.remove(cube_colliders, 1)
    oldest_cube_collider:destroy()
  end

  local half_spawn_area_size = CUBE_SPAWN_AREA_SIZE / 2
  local cube_x = (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_z = UPPER_ROOM_Z + (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_collider = physics_world:newBoxCollider(
    cube_x, CUBE_SPAWN_HEIGHT, cube_z,
    CUBE_SIZE, CUBE_SIZE, CUBE_SIZE
  )
  cube_collider:setTag("dynamic")
  cube_collider:setMass(CUBE_MASS)
  cube_collider:setFriction(CUBE_FRICTION)
  cube_collider:setContinuous(true)
  _set_random_orientation(cube_collider)
  table.insert(cube_colliders, cube_collider)
end

local function _add_floor_section(section)
  assertions.is_instance(section, FloorSection)

  table.insert(floor_sections, section)
  table.insert(
    floor_section_materials,
    _get_concrete_material(section.width / section.thickness, 1)
  )

  local collider = physics_world:newBoxCollider(
    section.x, section.top_y - section.thickness / 2, section.z,
    section.width, section.thickness, section.depth
  )
  collider:setTag("environment")
  collider:setFriction(FLOOR_FRICTION)
end

local function _add_wall(wall)
  assertions.is_instance(wall, Wall)

  table.insert(walls, wall)
  table.insert(
    wall_materials,
    _get_concrete_material(1, wall.height / wall.thickness)
  )

  local collider = physics_world:newBoxCollider(
    wall.x, wall.center_y, wall.z,
    wall.box_width, wall.height, wall.box_depth
  )
  collider:setTag("environment")
  collider:setFriction(WALL_FRICTION)
end

local function _add_room(room)
  assertions.is_instance(room, Room)

  _add_floor_section(FloorSection:new(
    0, room.floor_height, room.center_z,
    FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE,
    "room"
  ))

  local half_floor_size = FLOOR_SIZE / 2
  _add_wall(Wall:new(
    -half_floor_size, room.floor_height, room.center_z,
    FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS,
    "left",
    "room"
  ))
  _add_wall(Wall:new(
    half_floor_size, room.floor_height, room.center_z,
    FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS,
    "right",
    "room"
  ))

  local front_wall_offset = room.open_side == "positive" and -half_floor_size or half_floor_size
  _add_wall(Wall:new(
    0, room.floor_height, room.center_z + front_wall_offset,
    FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS,
    "front",
    "room"
  ))
end

local function _add_stairs()
  local half_floor_size = FLOOR_SIZE / 2
  for index = 1, STAIR_STEP_COUNT do
    local step_y = index * STAIR_STEP_HEIGHT
    local step_z = -STAIR_LENGTH / 2 + (index - 0.5) * STAIR_STEP_DEPTH
    _add_floor_section(FloorSection:new(
      0, step_y, step_z,
      FLOOR_SIZE, STAIR_STEP_HEIGHT, STAIR_STEP_DEPTH,
      "stair"
    ))
    _add_wall(Wall:new(
      -half_floor_size, step_y, step_z,
      STAIR_STEP_DEPTH, WALL_HEIGHT, WALL_COLLIDER_THICKNESS,
      "left",
      "stair"
    ))
    _add_wall(Wall:new(
      half_floor_size, step_y, step_z,
      STAIR_STEP_DEPTH, WALL_HEIGHT, WALL_COLLIDER_THICKNESS,
      "right",
      "stair"
    ))
  end
end

function lovr.load()
  lovr.system.setWindowFullscreen(is_fullscreen)
  _set_mouse_captured(true)

  skybox_texture = lovr.graphics.newTexture("resources/textures/skybox/skybox.png")

  local cube_texture = lovr.graphics.newTexture("resources/textures/cube/cube.png")
  cube_material = lovr.graphics.newMaterial({ texture = cube_texture })
  cube_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.25, 0.25, 0.25, 1),
    diffuse = lovr.math.newVec4(0.8, 0.8, 0.8, 1),
    specular = lovr.math.newVec4(0.08, 0.08, 0.08, 1),
    shininess = 8,
  })

  concrete_texture = lovr.graphics.newTexture("resources/textures/concrete/concrete.png")
  concrete_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.25, 0.25, 0.25, 1),
    diffuse = lovr.math.newVec4(0.75, 0.75, 0.75, 1),
    specular = lovr.math.newVec4(0.1, 0.1, 0.1, 1),
    shininess = 12,
  })

  local floor_texture = lovr.graphics.newTexture("resources/textures/floor/floor.png")
  floor_material = lovr.graphics.newMaterial({ texture = floor_texture, uvScale = {5, 5} })
  stair_floor_material = lovr.graphics.newMaterial({
    texture = floor_texture,
    uvScale = {5, STAIR_STEP_DEPTH},
  })
  floor_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.3, 0.3, 0.3, 1),
    diffuse = lovr.math.newVec4(0.9, 0.9, 0.9, 1),
    specular = lovr.math.newVec4(0.45, 0.45, 0.45, 1),
    shininess = 48,
  })

  local wall_texture = lovr.graphics.newTexture("resources/textures/wall/wall.png")
  wall_material = lovr.graphics.newMaterial({ texture = wall_texture, uvScale = {4, 1} })
  stair_wall_material = lovr.graphics.newMaterial({
    texture = wall_texture,
    uvScale = {4 * STAIR_STEP_DEPTH / FLOOR_SIZE, 1},
  })
  wall_shading_material = BaseShading.newMaterial({
    ambient = lovr.math.newVec4(0.25, 0.25, 0.25, 1),
    diffuse = lovr.math.newVec4(0.85, 0.85, 0.85, 1),
    specular = lovr.math.newVec4(0.1, 0.1, 0.1, 1),
    shininess = 12,
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

  physics_world = lovr.physics.newWorld({
    tags = {"player", "dynamic", "environment", "trigger"},
    staticTags = {"environment"},
  })

  _add_room(Room:new(LOWER_ROOM_Z, 0, "positive"))
  _add_room(Room:new(UPPER_ROOM_Z, UPPER_ROOM_HEIGHT, "negative"))
  _add_stairs()

  player_controller = FPController:new(physics_world, {
    x = 0, y = PLAYER_START_Y, z = LOWER_ROOM_Z,
    height = PLAYER_HEIGHT,
    speed = PLAYER_SPEED,
    -- add a margin to the exact stair height for physics contact imprecision
    max_step_height = STAIR_STEP_HEIGHT + 0.02,
  })

  _spawn_cube()
end

function lovr.draw(pass)
  assertions.is_true(type(pass) == "userdata")

  -- a pass snapshots the current camera for every draw, so set it before recording scene draws
  pass:setViewPose(1, player_controller:get_camera_view_pose(), true)

  pass:skybox(skybox_texture)

  local camera_x, camera_y, camera_z = player_controller:get_camera_position()
  local camera_direction_x, camera_direction_y, camera_direction_z =
    player_controller:get_camera_direction()
  local camera_direction =
    lovr.math.newVec3(camera_direction_x, camera_direction_y, camera_direction_z)
  local camera_right = lovr.math.newVec3(-camera_direction_z, 0, camera_direction_x):normalize()
  local camera_right_x, _, camera_right_z = camera_right:unpack()
  lights[FLASHLIGHT_LIGHT_INDEX].spotDirection = camera_direction
  lights[FLASHLIGHT_LIGHT_INDEX].position = lovr.math.newVec4(
    camera_x + camera_right_x * FLASHLIGHT_RIGHT_OFFSET,
    camera_y - FLASHLIGHT_DOWN_OFFSET,
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
      30 -- far
    )
  else
    lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    shadow.lightIndex = MOON_LIGHT_INDEX

    local moon_x, moon_y, moon_z = lights[MOON_LIGHT_INDEX].position:unpack()
    base_shading:sendDirectionalShadow(
      lovr.math.newVec3(
        moon_x * MOON_SHADOW_DISTANCE,
        moon_y * MOON_SHADOW_DISTANCE,
        moon_z * MOON_SHADOW_DISTANCE
      ),
      lovr.math.newVec3(-moon_x, -moon_y, -moon_z),
      MOON_SHADOW_ORTHOGRAPHIC_SIZE,
      8, -- near
      20 -- far
    )
  end

  pass:setShader(surface_shader)
  base_shading:sendAmbient(pass, ambient)
  base_shading:sendLights(pass, lights)
  base_shading:sendShadow(pass, shadow)
  base_shading:sendFog(pass, BaseShading.noFog)

  base_shading:sendMaterial(pass, concrete_shading_material)
  for index, section in ipairs(floor_sections) do
    local box_y = section.top_y - section.thickness / 2
    pass:setMaterial(floor_section_materials[index])
    pass:box(
      section.x, box_y, section.z,
      section.width, section.thickness, section.depth,
      0, 0, 1, 0,
      "fill"
    )
    base_shading.shadowPass:box(
      section.x, box_y, section.z,
      section.width, section.thickness, section.depth,
      0, 0, 1, 0,
      "fill"
    )
  end
  for index, wall in ipairs(walls) do
    pass:setMaterial(wall_materials[index])
    pass:box(
      wall.x, wall.center_y, wall.z,
      wall.box_width, wall.height, wall.box_depth,
      0, 0, 1, 0,
      "fill"
    )
    base_shading.shadowPass:box(
      wall.x, wall.center_y, wall.z,
      wall.box_width, wall.height, wall.box_depth,
      0, 0, 1, 0,
      "fill"
    )
  end

  base_shading:sendMaterial(pass, floor_shading_material)
  for _, section in ipairs(floor_sections) do
    if section.surface_kind == "stair" then
      pass:setMaterial(stair_floor_material)
    else
      pass:setMaterial(floor_material)
    end

    local plane_y = section.top_y + FLOOR_PLANE_OFFSET
    pass:plane(
      section.x, plane_y, section.z,
      section.width, section.depth,
      -math.pi / 2, 1, 0, 0,
      "fill"
    )
    base_shading.shadowPass:plane(
      section.x, plane_y, section.z,
      section.width, section.depth,
      -math.pi / 2, 1, 0, 0,
      "fill"
    )
  end

  base_shading:sendMaterial(pass, wall_shading_material)
  for _, wall in ipairs(walls) do
    if wall.surface_kind == "stair" then
      pass:setMaterial(stair_wall_material)
    else
      pass:setMaterial(wall_material)
    end

    local normal_x, normal_z = math.sin(wall.angle), math.cos(wall.angle)
    local plane_offset = wall.thickness / 2 + FLOOR_PLANE_OFFSET
    local inner_x, inner_z = wall.x + normal_x * plane_offset, wall.z + normal_z * plane_offset
    local outer_x, outer_z = wall.x - normal_x * plane_offset, wall.z - normal_z * plane_offset
    pass:plane(
      inner_x, wall.center_y, inner_z,
      wall.width, wall.height,
      wall.angle, 0, 1, 0,
      "fill"
    )
    pass:plane(
      outer_x, wall.center_y, outer_z,
      wall.width, wall.height,
      wall.angle + math.pi, 0, 1, 0,
      "fill"
    )
  end

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

  -- apply the player's forces before advancing the physics simulation so they
  -- affect the current frame rather than the next one
  local input_x, input_z = _get_normalized_input()
  player_controller:pre_physics_update(dt, input_x, input_z)

  physics_world:update(dt)

  cube_spawn_timer = cube_spawn_timer + dt
  if cube_spawn_timer >= CUBE_SPAWN_INTERVAL then
    _spawn_cube()
    cube_spawn_timer = cube_spawn_timer - CUBE_SPAWN_INTERVAL
  end
end

function lovr.focus(focused)
  assertions.is_boolean(focused)

  _set_mouse_captured(focused)
end

function lovr.keypressed(key)
  assertions.is_string(key)

  if key == "f" then
    is_flashlight_enabled = not is_flashlight_enabled
  end

  if key == "r" then
    player_controller:teleport(0, PLAYER_START_Y, LOWER_ROOM_Z)
  end

  if key == "f11" then
    is_fullscreen = not is_fullscreen
    lovr.system.setWindowFullscreen(is_fullscreen)
  end

  if key == "escape" then
    lovr.event.quit()
  end
end

function lovr.mousemoved(_, _, dx, dy)
  assertions.is_number(dx)
  assertions.is_number(dy)

  if is_mouse_captured then
    player_controller:apply_mouse_move(dx, dy)
  end
end
