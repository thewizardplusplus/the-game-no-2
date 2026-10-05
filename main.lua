local require_paths =
  {"?.lua", "?/init.lua", "vendor/?.lua", "vendor/?/init.lua"}
lovr.filesystem.setRequirePath(table.concat(require_paths, ";"))

local assertions = require("luatypechecks.assertions")
local BaseShading = require("lovr-base-shading")
local FloorSection = require("models.floorsection")
local Room = require("models.room")
local Wall = require("models.wall")
local FPController = require("pkg.fpcontroller.fpcontroller")
local CarryController = require("pkg.fpcontroller.carrycontroller")

local PLAYER_HEIGHT = 1.8
local PLAYER_START_BOTTOM_Y = 5
local PLAYER_START_Y = PLAYER_START_BOTTOM_Y + PLAYER_HEIGHT / 2
local PLAYER_SPEED = 1.7
local MOON_LIGHT_INDEX = 1
local MOON_DIRECTION = vector(0.321, 0.767, 0.555):normalize()
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
local MAXIMUM_CARRY_MASS = 40
local CARRY_MASS_AT_MINIMUM_SPEED = 20
local MINIMUM_CARRY_SPEED_SCALE = 0.5
local MAXIMUM_CARRY_SPEED_LOSS = 1 - MINIMUM_CARRY_SPEED_SCALE
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
local ambient = nil -- {number,number,number,number}
local lights = {} -- {BaseLight,...}
local is_flashlight_enabled = true
local shadow = BaseShading.newShadow({ bias = 0.0001 }) -- BaseShadow
local physics_world = nil -- World
local player_controller = nil -- FPController
local carry_controller = nil -- CarryController
local cube_colliders = {} -- {Collider,...}
local persistent_cube_colliders = {} -- {[Collider]=boolean,...}
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
  return {red, green, blue, 1}
end

local function _set_random_orientation(collider)
  assertions.is_true(type(collider) == "userdata")

  local x_angle = (2 * math.pi) * lovr.math.random()
  local y_angle = (2 * math.pi) * lovr.math.random()
  local z_angle = (2 * math.pi) * lovr.math.random()
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
    local oldest_cube_collider_index = nil
    for index, cube_collider in ipairs(cube_colliders) do
      if not persistent_cube_colliders[cube_collider] then
        oldest_cube_collider_index = index
        break
      end
    end
    if oldest_cube_collider_index ~= nil then
      local oldest_cube_collider = table.remove(cube_colliders, oldest_cube_collider_index)
      oldest_cube_collider:destroy()
    end
  end

  local half_spawn_area_size = CUBE_SPAWN_AREA_SIZE / 2
  local cube_x = (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_z = UPPER_ROOM_Z + (2 * lovr.math.random() - 1) * half_spawn_area_size
  local cube_collider = physics_world:newBoxCollider(
    vector(cube_x, CUBE_SPAWN_HEIGHT, cube_z),
    vector(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
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
  table.insert(floor_section_materials, _get_concrete_material(section.size.x / section.size.y, 1))

  local collider_position = section.position - vector(0, section.size.y / 2, 0)
  local collider = physics_world:newBoxCollider(collider_position, section.size)
  collider:setTag("environment")
  collider:setFriction(FLOOR_FRICTION)
end

local function _add_wall(wall)
  assertions.is_instance(wall, Wall)

  table.insert(walls, wall)
  table.insert(wall_materials, _get_concrete_material(1, wall.size.y / wall.size.z))

  local collider = physics_world:newBoxCollider(wall.position, wall.size)
  collider:setOrientation(wall.orientation)
  collider:setTag("environment")
  collider:setFriction(WALL_FRICTION)
end

local function _add_room(room)
  assertions.is_instance(room, Room)

  _add_floor_section(FloorSection:new(
    room.floor_position,
    vector(FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE),
    "room"
  ))

  local half_floor_size = FLOOR_SIZE / 2
  _add_wall(Wall:new(
    room.floor_position + vector(-half_floor_size, 0, 0),
    vector(FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS),
    "left",
    "room"
  ))
  _add_wall(Wall:new(
    room.floor_position + vector(half_floor_size, 0, 0),
    vector(FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS),
    "right",
    "room"
  ))

  local front_wall_offset = room.open_side == "positive" and -half_floor_size or half_floor_size
  _add_wall(Wall:new(
    room.floor_position + vector(0, 0, front_wall_offset),
    vector(FLOOR_SIZE, WALL_HEIGHT, WALL_COLLIDER_THICKNESS),
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
      vector(0, step_y, step_z),
      vector(FLOOR_SIZE, STAIR_STEP_HEIGHT, STAIR_STEP_DEPTH),
      "stair"
    ))
    _add_wall(Wall:new(
      vector(-half_floor_size, step_y, step_z),
      vector(STAIR_STEP_DEPTH, WALL_HEIGHT, WALL_COLLIDER_THICKNESS),
      "left",
      "stair"
    ))
    _add_wall(Wall:new(
      vector(half_floor_size, step_y, step_z),
      vector(STAIR_STEP_DEPTH, WALL_HEIGHT, WALL_COLLIDER_THICKNESS),
      "right",
      "stair"
    ))
  end
end

local function _on_held_collider_changed(current_collider)
  if current_collider == nil then
    player_controller.speed_scale = 1
    return
  end

  persistent_cube_colliders[current_collider] = true

  local load_ratio = math.min(current_collider:getMass() / CARRY_MASS_AT_MINIMUM_SPEED, 1)
  player_controller.speed_scale = 1 - load_ratio * MAXIMUM_CARRY_SPEED_LOSS
end

function lovr.load()
  lovr.system.setWindowFullscreen(is_fullscreen)
  _set_mouse_captured(true)

  skybox_texture = lovr.graphics.newTexture("resources/textures/skybox/skybox.png")

  local cube_texture = lovr.graphics.newTexture("resources/textures/cube/cube.png")
  cube_material = lovr.graphics.newMaterial({ texture = cube_texture })
  cube_shading_material = BaseShading.newMaterial({
    ambient = {0.25, 0.25, 0.25, 1},
    diffuse = {0.8, 0.8, 0.8, 1},
    specular = {0.08, 0.08, 0.08, 1},
    shininess = 8,
  })

  concrete_texture = lovr.graphics.newTexture("resources/textures/concrete/concrete.png")
  concrete_shading_material = BaseShading.newMaterial({
    ambient = {0.25, 0.25, 0.25, 1},
    diffuse = {0.75, 0.75, 0.75, 1},
    specular = {0.1, 0.1, 0.1, 1},
    shininess = 12,
  })

  local floor_texture = lovr.graphics.newTexture("resources/textures/floor/floor.png")
  floor_material = lovr.graphics.newMaterial({ texture = floor_texture, uvScale = {5, 5} })
  stair_floor_material = lovr.graphics.newMaterial({
    texture = floor_texture,
    uvScale = {5, STAIR_STEP_DEPTH},
  })
  floor_shading_material = BaseShading.newMaterial({
    ambient = {0.3, 0.3, 0.3, 1},
    diffuse = {0.9, 0.9, 0.9, 1},
    specular = {0.45, 0.45, 0.45, 1},
    shininess = 48,
  })

  local wall_texture = lovr.graphics.newTexture("resources/textures/wall/wall.png")
  wall_material = lovr.graphics.newMaterial({ texture = wall_texture, uvScale = {4, 1} })
  stair_wall_material = lovr.graphics.newMaterial({
    texture = wall_texture,
    uvScale = {4 * STAIR_STEP_DEPTH / FLOOR_SIZE, 1},
  })
  wall_shading_material = BaseShading.newMaterial({
    ambient = {0.25, 0.25, 0.25, 1},
    diffuse = {0.85, 0.85, 0.85, 1},
    specular = {0.1, 0.1, 0.1, 1},
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

  lights[MOON_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[MOON_LIGHT_INDEX].position = {MOON_DIRECTION.x, MOON_DIRECTION.y, MOON_DIRECTION.z, 0}
  lights[MOON_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.494, 0.479)
  lights[MOON_LIGHT_INDEX].specular = _new_linear_color(0.5, 0.494, 0.479)

  lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_LIGHT_INDEX].spotCutoff = 35
  lights[FLASHLIGHT_LIGHT_INDEX].spotExponent = 2
  lights[FLASHLIGHT_LIGHT_INDEX].diffuse = {1, 1, 1, 1}
  lights[FLASHLIGHT_LIGHT_INDEX].specular = {1, 1, 1, 1}

  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotCutoff = 42.5
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotExponent = 2
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.5, 0.5)

  lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].diffuse = _new_linear_color(0.5, 0.46, 0.4)
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].linearAttenuation = 0.5
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].quadraticAttenuation = 0.5

  physics_world = lovr.physics.newWorld({
    tags = {"player", "dynamic", "held", "environment", "trigger"},
    staticTags = {"environment"},
  })
  physics_world:disableCollisionBetween("player", "held")

  _add_room(Room:new(vector(0, 0, LOWER_ROOM_Z), "positive"))
  _add_room(Room:new(vector(0, UPPER_ROOM_HEIGHT, UPPER_ROOM_Z), "negative"))
  _add_stairs()

  player_controller = FPController:new(physics_world, {
    position = vector(0, PLAYER_START_Y, LOWER_ROOM_Z),
    height = PLAYER_HEIGHT,
    speed = PLAYER_SPEED,
    -- add a margin to the exact stair height for physics contact imprecision
    max_step_height = STAIR_STEP_HEIGHT + 0.02,
  })
  carry_controller = CarryController:new(physics_world, player_controller, {
    maximum_carry_mass = MAXIMUM_CARRY_MASS,
    hold_offset = vector(0, -0.2, -1),
    on_held_collider_changed = _on_held_collider_changed,
  })

  _spawn_cube()
end

function lovr.draw(pass)
  assertions.is_true(type(pass) == "userdata")

  -- a pass snapshots the current camera for every draw, so set it before recording scene draws
  local camera_position = player_controller:get_camera_position()
  local camera_orientation = player_controller:get_camera_orientation()
  pass:setViewPose(1, camera_position, camera_orientation)

  pass:skybox(skybox_texture)

  local camera_right = camera_orientation * vector.right
  local flashlight_direction = camera_orientation:direction()
  local flashlight_position = vector(
    camera_position.x + camera_right.x * FLASHLIGHT_RIGHT_OFFSET,
    camera_position.y - FLASHLIGHT_DOWN_OFFSET,
    camera_position.z + camera_right.z * FLASHLIGHT_RIGHT_OFFSET
  )
  local flashlight_uniform_position =
    {flashlight_position.x, flashlight_position.y, flashlight_position.z, 1}
  lights[FLASHLIGHT_LIGHT_INDEX].spotDirection = flashlight_direction
  lights[FLASHLIGHT_LIGHT_INDEX].position = flashlight_uniform_position
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].spotDirection = flashlight_direction
  lights[FLASHLIGHT_WIDE_LIGHT_INDEX].position = flashlight_uniform_position
  lights[FLASHLIGHT_FILL_LIGHT_INDEX].position = flashlight_uniform_position

  base_shading:resetShadowPass()
  if is_flashlight_enabled then
    lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kFragment
    shadow.lightIndex = FLASHLIGHT_LIGHT_INDEX

    base_shading:sendSpotlightShadow(
      flashlight_position,
      flashlight_direction,
      lights[FLASHLIGHT_LIGHT_INDEX].spotCutoff,
      0.1, -- near
      30 -- far
    )
  else
    lights[FLASHLIGHT_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_WIDE_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    lights[FLASHLIGHT_FILL_LIGHT_INDEX].mode = BaseShading.LightMode.kInactive
    shadow.lightIndex = MOON_LIGHT_INDEX

    base_shading:sendDirectionalShadow(
      MOON_DIRECTION * MOON_SHADOW_DISTANCE,
      -MOON_DIRECTION,
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
    local box_position = section.position - vector(0, section.size.y / 2, 0)
    pass:setMaterial(floor_section_materials[index])
    pass:box(box_position, section.size, quaternion.identity, "fill")
    base_shading.shadowPass:box(box_position, section.size, quaternion.identity, "fill")
  end
  for index, wall in ipairs(walls) do
    pass:setMaterial(wall_materials[index])
    pass:box(wall.position, wall.size, wall.orientation, "fill")
    base_shading.shadowPass:box(wall.position, wall.size, wall.orientation, "fill")
  end

  base_shading:sendMaterial(pass, floor_shading_material)
  for _, section in ipairs(floor_sections) do
    if section.surface_kind == "stair" then
      pass:setMaterial(stair_floor_material)
    else
      pass:setMaterial(floor_material)
    end

    local plane_position = section.position + vector(0, FLOOR_PLANE_OFFSET, 0)
    local plane_size = vector(section.size.x, section.size.z, 0)
    local plane_orientation = quaternion.angleaxis(-math.pi / 2, 1, 0, 0)
    pass:plane(plane_position, plane_size, plane_orientation, "fill")
    base_shading.shadowPass:plane(plane_position, plane_size, plane_orientation, "fill")
  end

  base_shading:sendMaterial(pass, wall_shading_material)
  for _, wall in ipairs(walls) do
    if wall.surface_kind == "stair" then
      pass:setMaterial(stair_wall_material)
    else
      pass:setMaterial(wall_material)
    end

    local plane_normal = wall.orientation * vector.backward
    local plane_offset = wall.size.z / 2 + FLOOR_PLANE_OFFSET
    local inner_plane_position = wall.position + plane_normal * plane_offset
    local outer_plane_position = wall.position - plane_normal * plane_offset
    local plane_size = vector(wall.size.x, wall.size.y, 0)
    local outer_plane_orientation = quaternion.angleaxis(math.pi, 0, 1, 0) * wall.orientation
    pass:plane(inner_plane_position, plane_size, wall.orientation, "fill")
    pass:plane(outer_plane_position, plane_size, outer_plane_orientation, "fill")
  end

  pass:setMaterial(cube_material)
  base_shading:sendMaterial(pass, cube_shading_material)
  for _, cube_collider in ipairs(cube_colliders) do
    local cube_position = vector(cube_collider:getPosition())
    local cube_orientation = quaternion.angleaxis(cube_collider:getOrientation())
    pass:cube(cube_position, CUBE_SIZE, cube_orientation, "fill")
    base_shading.shadowPass:cube(cube_position, CUBE_SIZE, cube_orientation, "fill")
  end

  return lovr.graphics.submit(base_shading.shadowPass, pass)
end

function lovr.update(dt)
  assertions.is_number(dt)

  -- apply the player's forces before advancing the physics simulation so they
  -- affect the current frame rather than the next one
  local input_x, input_z = _get_normalized_input()
  player_controller:pre_physics_update(dt, input_x, input_z)
  carry_controller:pre_physics_update(dt)

  physics_world:update(dt)
  carry_controller:post_physics_update(dt)

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

  if key == "e" then
    carry_controller:toggle()
  end

  if key == "f" then
    is_flashlight_enabled = not is_flashlight_enabled
  end

  if key == "r" then
    carry_controller:release()
    player_controller:teleport(vector(0, PLAYER_START_Y, LOWER_ROOM_Z))
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
