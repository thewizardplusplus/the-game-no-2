-- luacheck: no max comment line length

---
-- A physics-based first-person controller.
--
-- The controller uses a dynamic capsule and force-based horizontal movement. It provides mouse
-- look and camera poses, acceleration-limited walking, walkable ground detection, automatic
-- step-up, preserved airborne momentum, and limited pushing force against dynamic bodies. Call
-- @{FPController:pre_physics_update|FPController:pre_physics_update()} immediately before
-- advancing the physics world.
--
-- The controller is designed for mostly flat environments. It does not implement jumping,
-- crouching, traversable slopes, ground snapping, smooth step-up or step-down, or movement
-- inheritance from moving platforms. Camera effects, footsteps, interaction, and other gameplay
-- features are expected to be implemented by the game.
--
-- @classmod FPController

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local checks = require("luatypechecks.checks")

local _CAPSULE_ANGLE, _CAPSULE_AXIS_X, _CAPSULE_AXIS_Y, _CAPSULE_AXIS_Z = math.pi / 2, 1, 0, 0
local _MIN_VELOCITY_CORRECTION_TIME = 1 / 120
local _MIN_PREDICTED_DISPLACEMENT = 1e-6 -- meters
local _MIN_HORIZONTAL_NORMAL_LENGTH = 1e-6 -- dimensionless

local function _shallow_copy(data)
  assertions.is_table(data)

  local data_shallow_copy = {}
  for key, value in pairs(data) do
    data_shallow_copy[key] = value
  end

  return data_shallow_copy
end

---
-- @table instance
-- @tfield World world physics world containing the controller (**read-only**)
-- @tfield number yaw horizontal view angle
-- @tfield number pitch vertical view angle
-- @tfield number max_pitch maximum absolute vertical view angle
-- @tfield number mouse_sensitivity mouse sensitivity in radians per unit of relative mouse movement
-- @tfield boolean mouse_y_inverted whether vertical mouse look is inverted
-- @tfield number radius capsule radius (**read-only**)
-- @tfield number height total capsule height (**read-only**)
-- @tfield number eye_height eye height above capsule bottom
-- @tfield number mass player mass in kilograms (**read-only**)
-- @tfield number speed walking speed in meters per second
-- @tfield number max_acceleration maximum free walking acceleration in meters per second squared
-- @tfield number max_push_force force limit against dynamic bodies while movement input is nonzero, in newtons
-- @tfield number max_floor_angle maximum walkable floor angle
-- @tfield number max_step_height maximum automatic step height
-- @tfield number step_search_distance extra forward step search distance
-- @tfield number ground_tolerance groundedness check distance below capsule
-- @tfield number contact_tolerance near-contact and step clearance tolerance
-- @tfield string push_limit_filter push-limiting collision filter
-- @tfield string ground_filter groundedness query filter
-- @tfield string step_filter step-up collision filter
-- @tfield string obstruction_filter step-up obstruction query filter
-- @tfield Collider collider controller physics collider (**read-only**)
-- @tfield Collider|nil ground_collider collider currently serving as the controller's walkable ground, if any (**read-only**)
-- @tfield Shape|nil ground_shape shape currently serving as the controller's walkable ground, if any (**read-only**)

local FPController = middleclass("FPController")

---
-- @function new
-- @tparam World world physics world in which the controller will live
-- @tparam[opt={}] table options controller settings
-- @tparam[opt=0] number options.x initial X coordinate
-- @tparam[opt=0] number options.y initial capsule center Y coordinate
-- @tparam[opt=0] number options.z initial Z coordinate
-- @tparam[opt=0] number options.yaw initial horizontal view angle
-- @tparam[opt=0] number options.pitch initial vertical view angle
-- @tparam[opt=math.rad(89)] number options.max_pitch maximum absolute vertical view angle
-- @tparam[opt=0.0025] number options.mouse_sensitivity mouse sensitivity in radians per unit of relative mouse movement
-- @tparam[opt=false] boolean options.mouse_y_inverted whether vertical mouse look is inverted
-- @tparam[opt=0.3] number options.radius capsule radius
-- @tparam[opt=1.8] number options.height total capsule height
-- @tparam[opt=1.65] number options.eye_height eye height above capsule bottom
-- @tparam[opt=75] number options.mass player mass in kilograms
-- @tparam[opt=0] number options.friction capsule friction
-- @tparam[opt=2.5] number options.speed walking speed in meters per second
-- @tparam[opt=12] number options.max_acceleration maximum free walking acceleration in meters per second squared
-- @tparam[opt=350] number options.max_push_force force limit against dynamic bodies while movement input is nonzero, in newtons
-- @tparam[opt=math.rad(5)] number options.max_floor_angle maximum walkable floor angle
-- @tparam[opt=0.25] number options.max_step_height maximum automatic step height
-- @tparam[opt=0.08] number options.step_search_distance extra forward step search distance
-- @tparam[opt=0.08] number options.ground_tolerance groundedness check distance below capsule
-- @tparam[opt=0.01] number options.contact_tolerance near-contact and step clearance tolerance
-- @tparam[opt="player"] string options.tag collider tag
-- @tparam[opt="dynamic"] string options.push_limit_filter push-limiting collision filter
-- @tparam[opt] string options.ground_filter groundedness query filter; excludes `options.tag` and "trigger" by default
-- @tparam[opt="environment"] string options.step_filter step-up collision filter
-- @tparam[opt] string options.obstruction_filter step-up obstruction query filter; excludes `options.tag` and "trigger" by default
-- @treturn FPController
function FPController:initialize(world, options)
  assertions.is_true(type(world) == "userdata" or checks.is_table(world))
  assertions.is_table_or_nil(options)

  options = _shallow_copy(options or {})
  options.x = options.x or 0
  options.y = options.y or 0
  options.z = options.z or 0
  options.yaw = options.yaw or 0
  options.pitch = options.pitch or 0
  options.max_pitch = options.max_pitch or math.rad(89)
  options.mouse_sensitivity = options.mouse_sensitivity or 0.0025
  options.mouse_y_inverted = options.mouse_y_inverted or false
  options.radius = options.radius or 0.3
  options.height = options.height or 1.8
  options.eye_height = options.eye_height or 1.65
  options.mass = options.mass or 75
  options.friction = options.friction or 0
  options.speed = options.speed or 2.5
  options.max_acceleration = options.max_acceleration or 12
  options.max_push_force = options.max_push_force or 350
  options.max_floor_angle = options.max_floor_angle or math.rad(5)
  options.max_step_height = options.max_step_height or 0.25
  options.step_search_distance = options.step_search_distance or 0.08
  options.ground_tolerance = options.ground_tolerance or 0.08
  options.contact_tolerance = options.contact_tolerance or 0.01
  options.tag = options.tag or "player"
  options.push_limit_filter = options.push_limit_filter or "dynamic"
  options.ground_filter = options.ground_filter or string.format("~%s ~trigger", options.tag)
  options.step_filter = options.step_filter or "environment"
  options.obstruction_filter =
    options.obstruction_filter or string.format("~%s ~trigger", options.tag)

  assertions.is_number(options.x)
  assertions.is_number(options.y)
  assertions.is_number(options.z)
  assertions.is_number(options.yaw)
  assertions.is_number(options.pitch)
  assertions.is_number(options.max_pitch)
  assertions.is_number(options.mouse_sensitivity)
  assertions.is_boolean(options.mouse_y_inverted)
  assertions.is_number(options.radius)
  assertions.is_number(options.height)
  assertions.is_number(options.eye_height)
  assertions.is_number(options.mass)
  assertions.is_number(options.friction)
  assertions.is_number(options.speed)
  assertions.is_number(options.max_acceleration)
  assertions.is_number(options.max_push_force)
  assertions.is_number(options.max_floor_angle)
  assertions.is_number(options.max_step_height)
  assertions.is_number(options.step_search_distance)
  assertions.is_number(options.ground_tolerance)
  assertions.is_number(options.contact_tolerance)
  assertions.is_string(options.tag)
  assertions.is_string(options.push_limit_filter)
  assertions.is_string(options.ground_filter)
  assertions.is_string(options.step_filter)
  assertions.is_string(options.obstruction_filter)

  local collider = world:newCapsuleCollider(
    options.x, options.y, options.z,
    options.radius, options.height - 2 * options.radius
  )
  -- LÖVR capsules are aligned with the Z axis. Rotate the shape itself so
  -- the long axis is vertical while the collider remains rotation-locked.
  collider:getShape():setOffset(
    0, 0, 0,
    _CAPSULE_ANGLE, _CAPSULE_AXIS_X, _CAPSULE_AXIS_Y, _CAPSULE_AXIS_Z
  )
  collider:setTag(options.tag)
  collider:setMass(options.mass)
  collider:setFriction(options.friction)
  collider:setRestitution(0) -- inelastic collisions
  collider:setContinuous(true)
  collider:setSleepingAllowed(false)
  collider:setDegreesOfFreedom("xyz", "")

  self.world = world
  self.yaw = options.yaw % (2 * math.pi)
  self.pitch = math.max(-options.max_pitch, math.min(options.max_pitch, options.pitch))
  self.max_pitch = options.max_pitch
  self.mouse_sensitivity = options.mouse_sensitivity
  self.mouse_y_inverted = options.mouse_y_inverted
  self.radius = options.radius
  self.height = options.height
  self.eye_height = options.eye_height
  self.mass = options.mass
  self.speed = options.speed
  self.max_acceleration = options.max_acceleration
  self.max_push_force = options.max_push_force
  self.max_floor_angle = options.max_floor_angle
  self.max_step_height = options.max_step_height
  self.step_search_distance = options.step_search_distance
  self.ground_tolerance = options.ground_tolerance
  self.contact_tolerance = options.contact_tolerance
  self.push_limit_filter = options.push_limit_filter
  self.ground_filter = options.ground_filter
  self.step_filter = options.step_filter
  self.obstruction_filter = options.obstruction_filter
  self.collider = collider

  self:_clear_ground_hit()
end

---
-- @treturn number camera X coordinate
-- @treturn number camera Y coordinate
-- @treturn number camera Z coordinate
function FPController:get_camera_position()
  local x, y, z = self.collider:getPosition()
  return x, y - self.height / 2 + self.eye_height, z
end

---
-- @treturn number normalized view direction X component
-- @treturn number normalized view direction Y component
-- @treturn number normalized view direction Z component
function FPController:get_camera_direction()
  local cos_pitch = math.cos(self.pitch)
  return math.sin(self.yaw) * cos_pitch, math.sin(self.pitch), -math.cos(self.yaw) * cos_pitch
end

---
-- @treturn Mat4 camera view pose
function FPController:get_camera_view_pose()
  local x, y, z = self:get_camera_position()
  local dx, dy, dz = self:get_camera_direction()
  return lovr.math.newMat4():lookAt({x, y, z}, {x + dx, y + dy, z + dz})
end

---
-- ⚠️. Check whether the controller is standing on a sufficiently horizontal surface. This method
-- updates `ground_collider` and `ground_shape`, clearing them when no walkable ground is found.
-- @treturn boolean whether the controller is grounded
function FPController:is_grounded()
  local collider, shape, _, _, _, _, normal_y = self:_get_ground_hit_within(self.ground_tolerance)
  local is_grounded =
    collider ~= nil and normal_y ~= nil and normal_y >= math.cos(self.max_floor_angle)

  if is_grounded then
    self.ground_collider = collider
    self.ground_shape = shape
  else
    self:_clear_ground_hit()
  end

  return is_grounded
end

---
-- ⚠️. Update walking. Horizontal forces are applied while grounded or near horizontal ground
-- within step height. This keeps small drops controllable while longer falls preserve horizontal
-- momentum. Forces are used instead of overwriting velocity, so contacts with dynamic bodies
-- remain bidirectional. This method updates `ground_collider` and `ground_shape` with the current
-- grounded contact, or clears them when not grounded.
-- @tparam number dt frame duration
-- @tparam number input_x local movement input along the X axis
-- @tparam number input_z local movement input along the Z axis
function FPController:pre_physics_update(dt, input_x, input_z)
  assertions.is_number(dt)
  assertions.is_number(input_x)
  assertions.is_number(input_z)

  local is_grounded = self:is_grounded()
  if not is_grounded then
    local step_search_height = self.max_step_height + self.contact_tolerance
    local near_ground_tolerance = math.max(step_search_height, self.ground_tolerance)
    local collider, _, _, _, _, _, normal_y = self:_get_ground_hit_within(near_ground_tolerance)
    local is_near_ground =
      collider ~= nil and normal_y ~= nil and normal_y >= math.cos(self.max_floor_angle)
    if not is_near_ground then
      return
    end
  end

  local input_length = math.sqrt(input_x * input_x + input_z * input_z)
  -- preserve analog input magnitude; only clamp vectors longer than one
  if input_length > 1 then
    input_x, input_z = input_x / input_length, input_z / input_length
  end

  local sin_yaw, cos_yaw = math.sin(self.yaw), math.cos(self.yaw)
  local direction_x = input_x * cos_yaw - input_z * sin_yaw
  local direction_z = input_x * sin_yaw + input_z * cos_yaw

  local normalized_direction_x, normalized_direction_z
  local has_input = input_x ~= 0 or input_z ~= 0
  if has_input then
    local direction_length = math.sqrt(direction_x * direction_x + direction_z * direction_z)
    normalized_direction_x = direction_x / direction_length
    normalized_direction_z = direction_z / direction_length
  end

  local force_x, force_z = self:_calculate_horizontal_force(dt, direction_x, direction_z, has_input)
  self.collider:applyForce(force_x, 0, force_z)

  if has_input then
    self:_try_step(normalized_direction_x, normalized_direction_z, is_grounded)
  end
end

---
-- ⚠️. Apply relative mouse movement to the view angles.
-- @tparam number dx horizontal relative motion
-- @tparam number dy vertical relative motion
function FPController:apply_mouse_move(dx, dy)
  assertions.is_number(dx)
  assertions.is_number(dy)

  self.yaw = (self.yaw + dx * self.mouse_sensitivity) % (2 * math.pi)

  local pitch_sign = self.mouse_y_inverted and 1 or -1
  local pitch = self.pitch + dy * self.mouse_sensitivity * pitch_sign
  self.pitch = math.max(-self.max_pitch, math.min(self.max_pitch, pitch))
end

---
-- ⚠️. Move the controller immediately and discard its linear momentum.
-- @tparam number x target X coordinate
-- @tparam number y target capsule center Y coordinate
-- @tparam number z target Z coordinate
function FPController:teleport(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  self.collider:setPosition(x, y, z)
  self.collider:setLinearVelocity(0, 0, 0)
  self:_clear_ground_hit()
end

function FPController:_clear_ground_hit()
  self.ground_collider, self.ground_shape = nil, nil
end

function FPController:_get_ground_hit_within(distance)
  assertions.is_number(distance)

  local x, y, z = self.collider:getPosition()
  local bottom = y - self.height / 2
  return self.world:raycast(
    x, bottom + self.contact_tolerance, z,
    x, bottom - distance, z,
    self.ground_filter
  )
end

function FPController:_calculate_horizontal_force(dt, direction_x, direction_z, has_input)
  assertions.is_number(dt)
  assertions.is_number(direction_x)
  assertions.is_number(direction_z)
  assertions.is_boolean(has_input)

  local desired_velocity_x, desired_velocity_z = direction_x * self.speed, direction_z * self.speed
  local velocity_x, _, velocity_z = self.collider:getLinearVelocity()
  local velocity_correction_time = math.max(dt, _MIN_VELOCITY_CORRECTION_TIME)
  local force_x = (desired_velocity_x - velocity_x) * self.mass / velocity_correction_time
  local force_z = (desired_velocity_z - velocity_z) * self.mass / velocity_correction_time
  local force_length = math.sqrt(force_x * force_x + force_z * force_z)
  local maximum_force = self.mass * self.max_acceleration
  if force_length > maximum_force then
    force_x = force_x / force_length * maximum_force
    force_z = force_z / force_length * maximum_force
  end

  if not has_input then
    return force_x, force_z
  end

  return self:_limit_push_force(dt, velocity_x, velocity_z, force_x, force_z)
end

function FPController:_limit_push_force(dt, velocity_x, velocity_z, force_x, force_z)
  assertions.is_number(dt)
  assertions.is_number(velocity_x)
  assertions.is_number(velocity_z)
  assertions.is_number(force_x)
  assertions.is_number(force_z)

  local predicted_velocity_x = velocity_x + force_x / self.mass * dt
  local predicted_velocity_z = velocity_z + force_z / self.mass * dt
  local predicted_displacement_x = predicted_velocity_x * dt
  local predicted_displacement_z = predicted_velocity_z * dt
  local predicted_displacement_length = math.sqrt(
    predicted_displacement_x * predicted_displacement_x
      + predicted_displacement_z * predicted_displacement_z
  )
  if predicted_displacement_length <= _MIN_PREDICTED_DISPLACEMENT then
    return force_x, force_z
  end

  predicted_displacement_x = predicted_displacement_x
    + predicted_displacement_x / predicted_displacement_length * self.contact_tolerance
  predicted_displacement_z = predicted_displacement_z
    + predicted_displacement_z / predicted_displacement_length * self.contact_tolerance

  local dynamic_collider, hit_x, hit_y, hit_z, normal_x, normal_z =
    self:_get_dynamic_body_ahead(predicted_displacement_x, predicted_displacement_z)
  if dynamic_collider == nil or normal_x == nil or normal_z == nil then
    return force_x, force_z
  end

  local horizontal_normal_length = math.sqrt(normal_x * normal_x + normal_z * normal_z)
  if horizontal_normal_length <= _MIN_HORIZONTAL_NORMAL_LENGTH then
    return force_x, force_z
  end

  normal_x = normal_x / horizontal_normal_length
  normal_z = normal_z / horizontal_normal_length

  local surface_velocity_x, _, surface_velocity_z =
    dynamic_collider:getLinearVelocityFromWorldPoint(hit_x, hit_y, hit_z)
  local relative_velocity_along_normal =
    (predicted_velocity_x - surface_velocity_x) * normal_x
    + (predicted_velocity_z - surface_velocity_z) * normal_z
  if relative_velocity_along_normal >= 0 then
    return force_x, force_z
  end

  local force_along_normal = force_x * normal_x + force_z * normal_z
  if force_along_normal >= -self.max_push_force then
    return force_x, force_z
  end

  local correction = -self.max_push_force - force_along_normal
  return force_x + normal_x * correction, force_z + normal_z * correction
end

function FPController:_get_dynamic_body_ahead(displacement_x, displacement_z)
  assertions.is_number(displacement_x)
  assertions.is_number(displacement_z)

  local x, y, z = self.collider:getPosition()
  local collider, _, hit_x, hit_y, hit_z, normal_x, _, normal_z = self.world:shapecast(
    self.collider:getShape(),
    x, y, z,
    x + displacement_x, y, z + displacement_z,
    _CAPSULE_ANGLE, _CAPSULE_AXIS_X, _CAPSULE_AXIS_Y, _CAPSULE_AXIS_Z,
    self.push_limit_filter
  )
  return collider, hit_x, hit_y, hit_z, normal_x, normal_z
end

function FPController:_try_step(direction_x, direction_z, is_grounded)
  assertions.is_number(direction_x)
  assertions.is_number(direction_z)
  assertions.is_boolean(is_grounded)

  if self.max_step_height == 0 or not is_grounded then
    return
  end

  local x, y, z = self.collider:getPosition()
  local distance = self.radius + self.step_search_distance
  local ahead_x, ahead_z = x + direction_x * distance, z + direction_z * distance
  local bottom = y - self.height / 2
  local step_search_height = self.max_step_height + self.contact_tolerance
  local collider, _, _, hit_y, _, _, normal_y = self.world:raycast(
    ahead_x, bottom + step_search_height, ahead_z,
    ahead_x, bottom - self.ground_tolerance, ahead_z,
    self.step_filter
  )
  if collider == nil or normal_y == nil or normal_y < math.cos(self.max_floor_angle) then
    return
  end

  local rise = hit_y - bottom
  if rise <= self.contact_tolerance or rise > self.max_step_height then
    return
  end

  local target_y = y + rise + self.contact_tolerance
  local obstruction = self.world:overlapShape(
    self.collider:getShape(),
    x, target_y, z,
    _CAPSULE_ANGLE, _CAPSULE_AXIS_X, _CAPSULE_AXIS_Y, _CAPSULE_AXIS_Z,
    0, -- maximum distance
    self.obstruction_filter
  )
  if obstruction == nil then
    self.collider:setPosition(x, target_y, z)
  end
end

return FPController
