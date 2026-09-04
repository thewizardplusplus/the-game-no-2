-- luacheck: no max comment line length

---
-- A physics-based object carrying controller.
--
-- The controller raycasts from a camera provider to acquire dynamic colliders and uses
-- a `PoseController` to move a held collider towards a pose in front of the camera. The collider
-- remains dynamic, so collisions and release momentum are handled by the physics simulation.
-- Call @{CarryController:pre_physics_update|CarryController:pre_physics_update()} immediately
-- before advancing the physics world
-- and @{CarryController:post_physics_update|CarryController:post_physics_update()} immediately
-- after.
--
-- The camera provider must implement `get_camera_position()` and either `get_camera_orientation()`
-- or `get_camera_direction()`. The former is preferred when both are available because it preserves
-- the complete camera rotation, including roll. A direction-only provider is interpreted as having
-- no roll.
--
-- @classmod CarryController

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local checks = require("luatypechecks.checks")
local PoseController = require("pkg.fpcontroller.posecontroller")
local collider_utils = require("pkg.fpcontroller.utils.collider")
local rotation = require("pkg.fpcontroller.utils.rotation")
local utils = require("pkg.fpcontroller.utils")
local vector = require("pkg.fpcontroller.utils.vector")

local function _get_camera_direction_and_orientation(camera_provider)
  assertions.is_table(camera_provider)

  local has_camera_orientation = checks.has_methods(camera_provider, {"get_camera_orientation"})
  assertions.is_true(
    has_camera_orientation
      or checks.has_methods(camera_provider, {"get_camera_direction"})
  )

  if has_camera_orientation then
    local orientation = camera_provider:get_camera_orientation()
    local direction_x, direction_y, direction_z = rotation.to_camera_direction(orientation)
    return direction_x, direction_y, direction_z, orientation
  end

  local direction_x, direction_y, direction_z = camera_provider:get_camera_direction()
  local orientation = rotation.from_camera_direction(direction_x, direction_y, direction_z)
  return direction_x, direction_y, direction_z, orientation
end

---
-- @table instance
-- @tfield World world physics world containing carryable colliders (**read-only**)
-- @tfield table camera_provider camera pose provider (**read-only**)
-- @tfield number interaction_distance maximum acquisition distance, in meters
-- @tfield number maximum_carry_mass maximum acquired collider mass, in kilograms
-- @tfield number hold_distance target distance in front of the camera, in meters
-- @tfield number hold_offset_x horizontal target offset in camera-local coordinates, in meters
-- @tfield number hold_offset_y vertical target offset in camera-local coordinates, in meters
-- @tfield number pull_speed speed used to bring an acquired collider to hold distance
-- @tfield number held_linear_damping linear damping used while a collider is held
-- @tfield number held_angular_damping angular damping used while a collider is held
-- @tfield number break_distance sustained position error required to release, in meters
-- @tfield number break_duration time the error must remain excessive before release, in seconds
-- @tfield string interaction_filter raycast filter used to find the first visible collider
-- @tfield string carryable_tag tag required on an acquired collider
-- @tfield string held_tag temporary tag assigned to an acquired collider
-- @tfield table pose_controller_options options passed to @{PoseController:new|PoseController:new()}
-- @tfield function on_held_collider_changed callback invoked after the held collider changes, with the current and previous colliders
-- @tfield Collider|nil held_collider currently held collider, if any (**read-only**)
-- @tfield PoseController|nil pose_controller active pose controller, if any (**read-only**)
-- @tfield string|nil held_original_tag held collider tag to restore on release (**read-only**)
-- @tfield number|nil held_original_linear_damping held collider linear damping to restore on release (**read-only**)
-- @tfield number|nil held_original_angular_damping held collider angular damping to restore on release (**read-only**)
-- @tfield number|nil held_original_gravity_scale held collider gravity scale to restore on release (**read-only**)
-- @tfield number|nil current_hold_distance current target distance in front of the camera, in meters (**read-only**)
-- @tfield table|nil held_relative_orientation held collider orientation relative to the camera (**read-only**)
-- @tfield number break_timer duration of the current excessive position error, in seconds (**read-only**)

local CarryController = middleclass("CarryController")

---
-- @function new
-- @tparam World world physics world containing carryable colliders
-- @tparam table camera_provider camera pose provider
-- @tparam[opt={}] table options controller settings
-- @tparam[opt=2.5] number options.interaction_distance maximum acquisition distance, in meters
-- @tparam[opt=math.huge] number options.maximum_carry_mass maximum acquired collider mass, in kilograms
-- @tparam[opt=1] number options.hold_distance target distance in front of the camera, in meters
-- @tparam[opt=0] number options.hold_offset_x horizontal target offset in camera-local coordinates, in meters
-- @tparam[opt=0] number options.hold_offset_y vertical target offset in camera-local coordinates, in meters
-- @tparam[opt=6] number options.pull_speed speed used to bring an acquired collider to hold distance
-- @tparam[opt=0.8] number options.held_linear_damping linear damping used while a collider is held
-- @tparam[opt=0.95] number options.held_angular_damping angular damping used while a collider is held
-- @tparam[opt=0.75] number options.break_distance sustained position error required to release, in meters
-- @tparam[opt=0.25] number options.break_duration time the error must remain excessive before release, in seconds
-- @tparam[opt="~player ~trigger ~held"] string options.interaction_filter raycast filter used to find the first visible collider
-- @tparam[opt="dynamic"] string options.carryable_tag tag required on an acquired collider
-- @tparam[opt="held"] string options.held_tag temporary tag assigned to an acquired collider
-- @tparam[opt={}] table options.pose_controller_options options passed to @{PoseController:new|PoseController:new()}
-- @tparam[opt=no-op] function options.on_held_collider_changed callback invoked after the held collider changes, with the current and previous colliders
-- @treturn CarryController
function CarryController:initialize(world, camera_provider, options)
  assertions.is_true(type(world) == "userdata" or checks.is_table(world))
  assertions.is_table(camera_provider)
  assertions.has_methods(camera_provider, {"get_camera_position"})
  assertions.is_true(
    checks.has_methods(camera_provider, {"get_camera_direction"})
      or checks.has_methods(camera_provider, {"get_camera_orientation"})
  )
  assertions.is_table_or_nil(options)

  options = utils.shallow_copy(options or {})
  options.interaction_distance = options.interaction_distance or 2.5
  options.maximum_carry_mass = options.maximum_carry_mass or math.huge
  options.hold_distance = options.hold_distance or 1
  options.hold_offset_x = options.hold_offset_x or 0
  options.hold_offset_y = options.hold_offset_y or 0
  options.pull_speed = options.pull_speed or 6
  options.held_linear_damping = options.held_linear_damping or 0.8
  options.held_angular_damping = options.held_angular_damping or 0.95
  options.break_distance = options.break_distance or 0.75
  options.break_duration = options.break_duration or 0.25
  options.interaction_filter = options.interaction_filter or "~player ~trigger ~held"
  options.carryable_tag = options.carryable_tag or "dynamic"
  options.held_tag = options.held_tag or "held"
  options.pose_controller_options = options.pose_controller_options or {}
  options.on_held_collider_changed = options.on_held_collider_changed or function() end

  assertions.is_number(options.interaction_distance)
  assertions.is_number(options.maximum_carry_mass)
  assertions.is_number(options.hold_distance)
  assertions.is_number(options.hold_offset_x)
  assertions.is_number(options.hold_offset_y)
  assertions.is_number(options.pull_speed)
  assertions.is_number(options.held_linear_damping)
  assertions.is_number(options.held_angular_damping)
  assertions.is_number(options.break_distance)
  assertions.is_number(options.break_duration)
  assertions.is_string(options.interaction_filter)
  assertions.is_string(options.carryable_tag)
  assertions.is_string(options.held_tag)
  assertions.is_table(options.pose_controller_options)
  assertions.is_function(options.on_held_collider_changed)

  self.world = world
  self.camera_provider = camera_provider
  self.interaction_distance = options.interaction_distance
  self.maximum_carry_mass = options.maximum_carry_mass
  self.hold_distance = options.hold_distance
  self.hold_offset_x = options.hold_offset_x
  self.hold_offset_y = options.hold_offset_y
  self.pull_speed = options.pull_speed
  self.held_linear_damping = options.held_linear_damping
  self.held_angular_damping = options.held_angular_damping
  self.break_distance = options.break_distance
  self.break_duration = options.break_duration
  self.interaction_filter = options.interaction_filter
  self.carryable_tag = options.carryable_tag
  self.held_tag = options.held_tag
  self.pose_controller_options = utils.shallow_copy(options.pose_controller_options)
  self.on_held_collider_changed = options.on_held_collider_changed
  self.held_collider = nil
  self.pose_controller = nil
  self.held_original_tag = nil
  self.held_original_linear_damping = nil
  self.held_original_angular_damping = nil
  self.held_original_gravity_scale = nil
  self.current_hold_distance = nil
  self.held_relative_orientation = nil
  self.break_timer = 0
end

---
-- ⚠️. Acquire the first visible carryable collider, or release the current one.
-- @treturn boolean whether a collider is held after toggling
function CarryController:toggle()
  if self.held_collider ~= nil then
    self:release()
    return false
  end

  return self:acquire()
end

---
-- ⚠️. Acquire the first visible carryable collider unless one is already held.
-- @treturn boolean whether a collider is held after the attempt
function CarryController:acquire()
  if self.held_collider ~= nil then
    return true
  end

  local camera_x, camera_y, camera_z = self.camera_provider:get_camera_position()
  local direction_x, direction_y, direction_z, camera_orientation =
    _get_camera_direction_and_orientation(self.camera_provider)
  -- include non-carryable colliders so they can occlude carryable ones; acquisition eligibility
  -- is checked after finding the first visible collider
  local collider = self.world:raycast(
    camera_x, camera_y, camera_z,
    camera_x + direction_x * self.interaction_distance,
    camera_y + direction_y * self.interaction_distance,
    camera_z + direction_z * self.interaction_distance,
    self.interaction_filter
  )
  if
    collider == nil
      or collider:getTag() ~= self.carryable_tag
      or collider:getMass() > self.maximum_carry_mass
  then
    return false
  end

  local center_x, center_y, center_z = collider_utils.get_center_of_mass(collider)
  local center_distance =
    vector.length(center_x - camera_x, center_y - camera_y, center_z - camera_z)
  self:_start_holding(collider, center_distance, camera_orientation)

  return true
end

---
-- ⚠️. Stop controlling the held collider while preserving its current velocities.
function CarryController:release()
  if self.held_collider == nil then
    return
  end

  local previous_held_collider = self.held_collider
  previous_held_collider:setTag(self.held_original_tag)
  previous_held_collider:setLinearDamping(self.held_original_linear_damping)
  previous_held_collider:setAngularDamping(self.held_original_angular_damping)
  previous_held_collider:setGravityScale(self.held_original_gravity_scale)
  self.held_original_tag = nil
  self.held_original_linear_damping = nil
  self.held_original_angular_damping = nil
  self.held_original_gravity_scale = nil

  self.held_collider = nil
  self.pose_controller = nil
  self.current_hold_distance = nil
  self.held_relative_orientation = nil
  self.break_timer = 0

  self.on_held_collider_changed(nil, previous_held_collider)
end

---
-- ⚠️. Update the target pose and apply carrying forces.
-- Call immediately before the physics world update.
-- @tparam number dt frame duration
function CarryController:pre_physics_update(dt)
  assertions.is_number(dt)

  if self.held_collider == nil then
    return
  end

  local hold_distance_delta = self.hold_distance - self.current_hold_distance
  local maximum_hold_distance_delta = self.pull_speed * dt
  if math.abs(hold_distance_delta) > maximum_hold_distance_delta then
    hold_distance_delta = hold_distance_delta < 0
      and -maximum_hold_distance_delta
      or maximum_hold_distance_delta
  end
  self.current_hold_distance = self.current_hold_distance + hold_distance_delta

  local camera_x, camera_y, camera_z = self.camera_provider:get_camera_position()
  local _, _, _, camera_orientation = _get_camera_direction_and_orientation(self.camera_provider)
  local target_offset_x, target_offset_y, target_offset_z = rotation.rotate_vector(
    camera_orientation,
    self.hold_offset_x, self.hold_offset_y, -self.current_hold_distance
  )
  local target_orientation = rotation.multiply(camera_orientation, self.held_relative_orientation)
  local target_angle, target_axis_x, target_axis_y, target_axis_z =
    rotation.to_angle_axis(target_orientation)
  self.pose_controller:set_target_pose(
    camera_x + target_offset_x, camera_y + target_offset_y, camera_z + target_offset_z,
    target_angle, target_axis_x, target_axis_y, target_axis_z
  )
  self.pose_controller:pre_physics_update(dt)
end

---
-- ⚠️. Release a collider that has remained too far from its target.
-- Call immediately after the physics world update.
-- @tparam number dt frame duration
function CarryController:post_physics_update(dt)
  assertions.is_number(dt)

  if self.held_collider == nil then
    return
  end

  if self.pose_controller:get_position_error() <= self.break_distance then
    self.break_timer = 0
    return
  end

  -- self.pose_controller:get_position_error() > self.break_distance
  self.break_timer = self.break_timer + dt
  if self.break_timer >= self.break_duration then
    self:release()
  end
end

function CarryController:_start_holding(collider, center_distance, camera_orientation)
  assertions.is_true(type(collider) == "userdata" or checks.is_table(collider))
  assertions.is_number(center_distance)
  assertions.is_table(camera_orientation)

  self.held_original_tag = collider:getTag()
  self.held_original_linear_damping = collider:getLinearDamping()
  self.held_original_angular_damping = collider:getAngularDamping()
  self.held_original_gravity_scale = collider:getGravityScale()
  collider:setTag(self.held_tag)
  collider:setLinearDamping(self.held_linear_damping)
  collider:setAngularDamping(self.held_angular_damping)
  collider:setGravityScale(0)

  self.held_collider = collider
  self.pose_controller = PoseController:new(collider, self.pose_controller_options)
  self.current_hold_distance = center_distance
  self.held_relative_orientation = rotation.multiply(
    rotation.inverse(camera_orientation),
    collider_utils.get_orientation(collider)
  )
  self.break_timer = 0

  self.on_held_collider_changed(collider, nil)
end

return CarryController
