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
local utils = require("pkg.fpcontroller.utils")
local vectorutils = require("pkg.fpcontroller.utils.vector")

local _CAPSULE_ORIENTATION = quaternion.angleaxis(math.pi / 2, 1, 0, 0)
local _MIN_VELOCITY_CORRECTION_TIME = 1 / 120
local _MIN_PREDICTED_DISPLACEMENT = 1e-6 -- meters
local _MIN_HORIZONTAL_NORMAL_LENGTH = 1e-6 -- dimensionless

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
-- @tfield number speed_scale multiplier applied to walking speed
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
-- @tparam[opt=vector.zero] vector options.position initial capsule center position
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
-- @tparam[opt=1] number options.speed_scale multiplier applied to walking speed
-- @tparam[opt=12] number options.max_acceleration maximum free walking acceleration in meters per second squared
-- @tparam[opt=350] number options.max_push_force force limit against dynamic bodies while movement input is nonzero, in newtons
-- @tparam[opt=math.rad(5)] number options.max_floor_angle maximum walkable floor angle
-- @tparam[opt=0.25] number options.max_step_height maximum automatic step height
-- @tparam[opt=0.08] number options.step_search_distance extra forward step search distance
-- @tparam[opt=0.08] number options.ground_tolerance groundedness check distance below capsule
-- @tparam[opt=0.01] number options.contact_tolerance near-contact and step clearance tolerance
-- @tparam[opt="player"] string options.tag collider tag
-- @tparam[opt="dynamic"] string options.push_limit_filter push-limiting collision filter
-- @tparam[opt] string options.ground_filter groundedness query filter; excludes `options.tag`, "trigger", and "held" by default
-- @tparam[opt="environment"] string options.step_filter step-up collision filter
-- @tparam[opt] string options.obstruction_filter step-up obstruction query filter; excludes `options.tag`, "trigger", and "held" by default
-- @treturn FPController
function FPController:initialize(world, options)
  assertions.is_true(type(world) == "userdata" or checks.is_table(world))
  assertions.is_table_or_nil(options)

  options = utils.shallow_copy(options or {})
  options.position = options.position or vector.zero
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
  options.speed_scale = options.speed_scale or 1
  options.max_acceleration = options.max_acceleration or 12
  options.max_push_force = options.max_push_force or 350
  options.max_floor_angle = options.max_floor_angle or math.rad(5)
  options.max_step_height = options.max_step_height or 0.25
  options.step_search_distance = options.step_search_distance or 0.08
  options.ground_tolerance = options.ground_tolerance or 0.08
  options.contact_tolerance = options.contact_tolerance or 0.01
  options.tag = options.tag or "player"
  options.push_limit_filter = options.push_limit_filter or "dynamic"
  options.ground_filter = options.ground_filter or string.format("~%s ~trigger ~held", options.tag)
  options.step_filter = options.step_filter or "environment"
  options.obstruction_filter =
    options.obstruction_filter or string.format("~%s ~trigger ~held", options.tag)

  assertions.is_table(options.position)
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
  assertions.is_number(options.speed_scale)
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
    options.position,
    options.radius,
    options.height - 2 * options.radius
  )
  -- LÖVR capsules are aligned with the Z axis. Rotate the shape itself so
  -- the long axis is vertical while the collider remains rotation-locked.
  collider:getShape():setOffset(vector.zero, _CAPSULE_ORIENTATION)
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
  self.speed_scale = options.speed_scale
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
-- @treturn vector camera position
function FPController:get_camera_position()
  local position = vector(self.collider:getPosition())
  return position + vector(0, self.eye_height - self.height / 2, 0)
end

---
-- @treturn quaternion camera orientation
function FPController:get_camera_orientation()
  local yaw_orientation = quaternion.angleaxis(-self.yaw, 0, 1, 0)
  local pitch_orientation = quaternion.angleaxis(self.pitch, 1, 0, 0)
  return yaw_orientation * pitch_orientation
end

---
-- @treturn vector normalized view direction
function FPController:get_camera_direction()
  return self:get_camera_orientation():direction()
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
    self.ground_collider, self.ground_shape = collider, shape
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

  local input = vector(input_x, 0, input_z)
  -- preserve analog input magnitude; only clamp vectors longer than one
  input = vectorutils.limit_length(input, 1)

  local direction = quaternion.angleaxis(-self.yaw, 0, 1, 0) * input
  local has_input = input.x ~= 0 or input.z ~= 0
  local force = self:_calculate_horizontal_force(dt, direction, has_input)
  self.collider:applyForce(force)

  if has_input then
    self:_try_step(direction:normalize(), is_grounded)
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
-- @tparam vector position target capsule center position
function FPController:teleport(position)
  assertions.is_table(position)

  self.collider:setPosition(position)
  self.collider:setLinearVelocity(vector.zero)
  self:_clear_ground_hit()
end

function FPController:_clear_ground_hit()
  self.ground_collider, self.ground_shape = nil, nil
end

function FPController:_get_ground_hit_within(distance)
  assertions.is_number(distance)

  local bottom_position = vector(self.collider:getPosition()) - vector(0, self.height / 2, 0)
  local cast_start = bottom_position + vector(0, self.contact_tolerance, 0)
  local cast_finish = bottom_position - vector(0, distance, 0)
  return self.world:raycast(cast_start, cast_finish, self.ground_filter)
end

function FPController:_calculate_horizontal_force(dt, direction, has_input)
  assertions.is_number(dt)
  assertions.is_table(direction)
  assertions.is_boolean(has_input)

  local effective_speed = self.speed * self.speed_scale
  local desired_velocity = direction * effective_speed
  local velocity_x, _, velocity_z = self.collider:getLinearVelocity()
  local velocity = vector(velocity_x, 0, velocity_z)
  local velocity_correction_time = math.max(dt, _MIN_VELOCITY_CORRECTION_TIME)
  local force = (desired_velocity - velocity) * self.mass / velocity_correction_time

  local maximum_force = self.mass * self.max_acceleration
  force = vectorutils.limit_length(force, maximum_force)

  if not has_input then
    return force
  end

  return self:_limit_push_force(dt, velocity, force)
end

function FPController:_limit_push_force(dt, velocity, force)
  assertions.is_number(dt)
  assertions.is_table(velocity)
  assertions.is_table(force)

  local predicted_velocity = velocity + force / self.mass * dt
  local predicted_displacement = predicted_velocity * dt
  local predicted_displacement_length = predicted_displacement:length()
  if predicted_displacement_length <= _MIN_PREDICTED_DISPLACEMENT then
    return force
  end

  predicted_displacement = predicted_displacement
    + predicted_displacement / predicted_displacement_length * self.contact_tolerance

  local dynamic_collider, hit_position, normal =
    self:_get_dynamic_body_ahead(predicted_displacement)
  if dynamic_collider == nil or normal == nil then
    return force
  end

  local horizontal_normal = vector(normal.x, 0, normal.z)
  local horizontal_normal_length = horizontal_normal:length()
  if horizontal_normal_length <= _MIN_HORIZONTAL_NORMAL_LENGTH then
    return force
  end

  horizontal_normal = horizontal_normal:normalize()

  local surface_velocity_x, _, surface_velocity_z =
    dynamic_collider:getLinearVelocityFromWorldPoint(hit_position)
  local surface_velocity = vector(surface_velocity_x, 0, surface_velocity_z)
  local relative_velocity_along_normal =
    (predicted_velocity - surface_velocity):dot(horizontal_normal)
  if relative_velocity_along_normal >= 0 then
    return force
  end

  local force_along_normal = force:dot(horizontal_normal)
  if force_along_normal >= -self.max_push_force then
    return force
  end

  local correction = -self.max_push_force - force_along_normal
  return force + horizontal_normal * correction
end

function FPController:_get_dynamic_body_ahead(displacement)
  assertions.is_table(displacement)

  local cast_start = vector(self.collider:getPosition())
  local cast_finish = cast_start + displacement
  local collider, _, hit_x, hit_y, hit_z, normal_x, _, normal_z = self.world:shapecast(
    self.collider:getShape(),
    cast_start,
    cast_finish,
    _CAPSULE_ORIENTATION,
    self.push_limit_filter
  )
  local hit_position =
    (hit_x ~= nil and hit_y ~= nil and hit_z ~= nil) and vector(hit_x, hit_y, hit_z) or nil
  local normal = (normal_x ~= nil and normal_z ~= nil) and vector(normal_x, 0, normal_z) or nil
  return collider, hit_position, normal
end

function FPController:_try_step(direction, is_grounded)
  assertions.is_table(direction)
  assertions.is_boolean(is_grounded)

  if self.max_step_height == 0 or not is_grounded then
    return
  end

  local position = vector(self.collider:getPosition())
  local distance = self.radius + self.step_search_distance
  local ahead = position + direction * distance
  local bottom = position.y - self.height / 2
  local cast_origin = vector(ahead.x, bottom, ahead.z)
  local cast_start = cast_origin + vector(0, self.max_step_height + self.contact_tolerance, 0)
  local cast_finish = cast_origin - vector(0, self.ground_tolerance, 0)
  local collider, _, _, hit_y, _, _, normal_y =
    self.world:raycast(cast_start, cast_finish, self.step_filter)
  if collider == nil or normal_y == nil or normal_y < math.cos(self.max_floor_angle) then
    return
  end

  local rise = hit_y - bottom
  if rise <= self.contact_tolerance or rise > self.max_step_height then
    return
  end

  local target_position = position + vector(0, rise + self.contact_tolerance, 0)
  local obstruction = self.world:overlapShape(
    self.collider:getShape(),
    target_position,
    _CAPSULE_ORIENTATION,
    0, -- maximum distance
    self.obstruction_filter
  )
  if obstruction == nil then
    self.collider:setPosition(target_position)
  end
end

return FPController
