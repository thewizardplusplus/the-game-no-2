-- luacheck: no max comment line length

---
-- A force-based controller that moves a dynamic collider towards a target pose.
--
-- Position and orientation are controlled by independent proportional-derivative controllers.
-- The resulting linear and angular accelerations are bounded before being converted to force and
-- torque. The collider remains dynamic and retains the physics world's collision response.
--
-- The target position refers to the collider's center of mass. Call
-- @{PoseController:pre_physics_update|PoseController:pre_physics_update()}
-- immediately before advancing the physics world.
--
-- @classmod PoseController

local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local checks = require("luatypechecks.checks")
local collider_utils = require("pkg.fpcontroller.utils.collider")
local rotation = require("pkg.fpcontroller.utils.rotation")
local vector = require("pkg.fpcontroller.utils.vector")
local utils = require("pkg.fpcontroller.utils")

---
-- @table instance
-- @tfield Collider collider controlled dynamic collider (**read-only**)
-- @tfield number position_frequency position response frequency, in hertz
-- @tfield number position_damping position damping ratio
-- @tfield number rotation_frequency orientation response frequency, in hertz
-- @tfield number rotation_damping orientation damping ratio
-- @tfield number max_linear_speed maximum target linear speed, in meters per second
-- @tfield number max_angular_speed maximum target angular speed, in radians per second
-- @tfield number max_linear_acceleration maximum applied linear acceleration
-- @tfield number max_angular_acceleration maximum applied angular acceleration
-- @tfield number target_x target center-of-mass X coordinate (**read-only**)
-- @tfield number target_y target center-of-mass Y coordinate (**read-only**)
-- @tfield number target_z target center-of-mass Z coordinate (**read-only**)
-- @tfield table target_orientation target orientation quaternion (**read-only**)
-- @tfield number previous_target_x previous target X coordinate used to derive velocity (**read-only**)
-- @tfield number previous_target_y previous target Y coordinate used to derive velocity (**read-only**)
-- @tfield number previous_target_z previous target Z coordinate used to derive velocity (**read-only**)
-- @tfield table previous_target_orientation previous target orientation used to derive angular velocity (**read-only**)
-- @tfield number position_error latest center-of-mass position error magnitude (**read-only**)
-- @tfield number orientation_error latest orientation error magnitude, in radians (**read-only**)
-- @tfield number last_force_x last applied force X component (**read-only**)
-- @tfield number last_force_y last applied force Y component (**read-only**)
-- @tfield number last_force_z last applied force Z component (**read-only**)
-- @tfield number last_torque_x last applied torque X component (**read-only**)
-- @tfield number last_torque_y last applied torque Y component (**read-only**)
-- @tfield number last_torque_z last applied torque Z component (**read-only**)

local PoseController = middleclass("PoseController")

---
-- @function new
-- @tparam Collider collider dynamic collider to control
-- @tparam[opt={}] table options controller settings
-- @tparam[opt=5] number options.position_frequency position response frequency, in hertz
-- @tparam[opt=1] number options.position_damping position damping ratio
-- @tparam[opt=4] number options.rotation_frequency orientation response frequency, in hertz
-- @tparam[opt=1] number options.rotation_damping orientation damping ratio
-- @tparam[opt=8] number options.max_linear_speed maximum target linear speed, in meters per second
-- @tparam[opt=2 * (2 * math.pi)] number options.max_angular_speed maximum target angular speed, in radians per second
-- @tparam[opt=60] number options.max_linear_acceleration maximum applied linear acceleration
-- @tparam[opt=8 * (2 * math.pi)] number options.max_angular_acceleration maximum applied angular acceleration
-- @treturn PoseController
function PoseController:initialize(collider, options)
  assertions.is_true(type(collider) == "userdata" or checks.is_table(collider))
  assertions.is_table_or_nil(options)

  options = utils.shallow_copy(options or {})
  options.position_frequency = options.position_frequency or 5
  options.position_damping = options.position_damping or 1
  options.rotation_frequency = options.rotation_frequency or 4
  options.rotation_damping = options.rotation_damping or 1
  options.max_linear_speed = options.max_linear_speed or 8
  options.max_angular_speed = options.max_angular_speed or 2 * (2 * math.pi)
  options.max_linear_acceleration = options.max_linear_acceleration or 60
  options.max_angular_acceleration = options.max_angular_acceleration or 8 * (2 * math.pi)

  assertions.is_number(options.position_frequency)
  assertions.is_number(options.position_damping)
  assertions.is_number(options.rotation_frequency)
  assertions.is_number(options.rotation_damping)
  assertions.is_number(options.max_linear_speed)
  assertions.is_number(options.max_angular_speed)
  assertions.is_number(options.max_linear_acceleration)
  assertions.is_number(options.max_angular_acceleration)

  local target_x, target_y, target_z = collider_utils.get_center_of_mass(collider)
  local target_orientation = collider_utils.get_orientation(collider)

  self.collider = collider
  self.position_frequency = options.position_frequency
  self.position_damping = options.position_damping
  self.rotation_frequency = options.rotation_frequency
  self.rotation_damping = options.rotation_damping
  self.max_linear_speed = options.max_linear_speed
  self.max_angular_speed = options.max_angular_speed
  self.max_linear_acceleration = options.max_linear_acceleration
  self.max_angular_acceleration = options.max_angular_acceleration
  self.target_x, self.target_y, self.target_z = target_x, target_y, target_z
  self.target_orientation = target_orientation
  self.previous_target_x, self.previous_target_y, self.previous_target_z =
    target_x, target_y, target_z
  self.previous_target_orientation = target_orientation
  self.position_error = 0
  self.orientation_error = 0
  self.last_force_x, self.last_force_y, self.last_force_z = 0, 0, 0
  self.last_torque_x, self.last_torque_y, self.last_torque_z = 0, 0, 0
end

---
-- @treturn number magnitude of the current center-of-mass position error
function PoseController:get_position_error()
  self:_update_position_error()
  return self.position_error
end

---
-- @treturn number magnitude of the current orientation error, in radians
function PoseController:get_orientation_error()
  self:_update_orientation_error()
  return self.orientation_error
end

---
-- @treturn number last applied force X component
-- @treturn number last applied force Y component
-- @treturn number last applied force Z component
function PoseController:get_applied_force()
  return self.last_force_x, self.last_force_y, self.last_force_z
end

---
-- @treturn number last applied torque X component
-- @treturn number last applied torque Y component
-- @treturn number last applied torque Z component
function PoseController:get_applied_torque()
  return self.last_torque_x, self.last_torque_y, self.last_torque_z
end

---
-- ⚠️. Apply bounded force and torque towards the target pose.
-- @tparam number dt frame duration
function PoseController:pre_physics_update(dt)
  assertions.is_number(dt)

  local velocity_x, velocity_y, velocity_z = self.collider:getLinearVelocity()
  local target_velocity_x = (self.target_x - self.previous_target_x) / dt
  local target_velocity_y = (self.target_y - self.previous_target_y) / dt
  local target_velocity_z = (self.target_z - self.previous_target_z) / dt
  target_velocity_x, target_velocity_y, target_velocity_z = vector.limit_length(
    target_velocity_x, target_velocity_y, target_velocity_z,
    self.max_linear_speed
  )

  local position_angular_frequency = (2 * math.pi) * self.position_frequency
  local position_error_x, position_error_y, position_error_z = self:_update_position_error()
  local acceleration_x =
    position_angular_frequency ^ 2 * position_error_x +
    2 * self.position_damping * position_angular_frequency * (target_velocity_x - velocity_x)
  local acceleration_y =
    position_angular_frequency ^ 2 * position_error_y +
    2 * self.position_damping * position_angular_frequency * (target_velocity_y - velocity_y)
  local acceleration_z =
    position_angular_frequency ^ 2 * position_error_z +
    2 * self.position_damping * position_angular_frequency * (target_velocity_z - velocity_z)
  acceleration_x, acceleration_y, acceleration_z = vector.limit_length(
    acceleration_x, acceleration_y, acceleration_z,
    self.max_linear_acceleration
  )

  local mass = self.collider:getMass()
  self.last_force_x, self.last_force_y, self.last_force_z =
    acceleration_x * mass, acceleration_y * mass, acceleration_z * mass
  self.collider:applyForce(self.last_force_x, self.last_force_y, self.last_force_z)

  local target_orientation_delta =
    rotation.difference(self.previous_target_orientation, self.target_orientation)
  local target_angular_velocity_x, target_angular_velocity_y, target_angular_velocity_z =
    rotation.to_rotation_vector(target_orientation_delta)
  target_angular_velocity_x, target_angular_velocity_y, target_angular_velocity_z =
    vector.limit_length(
      target_angular_velocity_x / dt,
      target_angular_velocity_y / dt,
      target_angular_velocity_z / dt,
      self.max_angular_speed
    )

  local rotation_angular_frequency = (2 * math.pi) * self.rotation_frequency
  local orientation, rotation_error_x, rotation_error_y, rotation_error_z =
    self:_update_orientation_error()
  local angular_velocity_x, angular_velocity_y, angular_velocity_z =
    self.collider:getAngularVelocity()
  local angular_acceleration_x =
    rotation_angular_frequency ^ 2 * rotation_error_x +
    2 * self.rotation_damping * rotation_angular_frequency *
      (target_angular_velocity_x - angular_velocity_x)
  local angular_acceleration_y =
    rotation_angular_frequency ^ 2 * rotation_error_y +
    2 * self.rotation_damping * rotation_angular_frequency *
      (target_angular_velocity_y - angular_velocity_y)
  local angular_acceleration_z =
    rotation_angular_frequency ^ 2 * rotation_error_z +
    2 * self.rotation_damping * rotation_angular_frequency *
      (target_angular_velocity_z - angular_velocity_z)
  angular_acceleration_x, angular_acceleration_y, angular_acceleration_z = vector.limit_length(
    angular_acceleration_x, angular_acceleration_y, angular_acceleration_z,
    self.max_angular_acceleration
  )

  self.last_torque_x, self.last_torque_y, self.last_torque_z = self:_get_world_torque(
    orientation,
    angular_acceleration_x, angular_acceleration_y, angular_acceleration_z
  )
  self.collider:applyTorque(self.last_torque_x, self.last_torque_y, self.last_torque_z)

  self.previous_target_x, self.previous_target_y, self.previous_target_z =
    self.target_x, self.target_y, self.target_z
  self.previous_target_orientation = self.target_orientation
end

---
-- ⚠️. Set the desired center-of-mass position and collider orientation.
-- @tparam number x target center-of-mass X coordinate
-- @tparam number y target center-of-mass Y coordinate
-- @tparam number z target center-of-mass Z coordinate
-- @tparam number angle target orientation angle, in radians
-- @tparam number axis_x target orientation axis X component
-- @tparam number axis_y target orientation axis Y component
-- @tparam number axis_z target orientation axis Z component
function PoseController:set_target_pose(x, y, z, angle, axis_x, axis_y, axis_z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)
  assertions.is_number(angle)
  assertions.is_number(axis_x)
  assertions.is_number(axis_y)
  assertions.is_number(axis_z)

  self.target_x, self.target_y, self.target_z = x, y, z
  self.target_orientation = rotation.from_angle_and_axis(angle, axis_x, axis_y, axis_z)
end

function PoseController:_update_position_error()
  local x, y, z = collider_utils.get_center_of_mass(self.collider)
  local error_x, error_y, error_z = self.target_x - x, self.target_y - y, self.target_z - z
  self.position_error = vector.length(error_x, error_y, error_z)

  return error_x, error_y, error_z
end

function PoseController:_update_orientation_error()
  local orientation = collider_utils.get_orientation(self.collider)
  local orientation_delta = rotation.difference(orientation, self.target_orientation)
  local error_x, error_y, error_z = rotation.to_rotation_vector(orientation_delta)
  self.orientation_error = vector.length(error_x, error_y, error_z)

  return orientation, error_x, error_y, error_z
end

function PoseController:_get_world_torque(
  orientation,
  acceleration_x, acceleration_y, acceleration_z
)
  assertions.is_table(orientation)
  assertions.is_number(acceleration_x)
  assertions.is_number(acceleration_y)
  assertions.is_number(acceleration_z)

  local inertia_x, inertia_y, inertia_z,
    inertia_angle, inertia_axis_x, inertia_axis_y, inertia_axis_z = self.collider:getInertia()
  local inertia_orientation =
    rotation.from_angle_and_axis(inertia_angle, inertia_axis_x, inertia_axis_y, inertia_axis_z)
  local world_inertia_orientation = rotation.multiply(orientation, inertia_orientation)
  local inverse_world_inertia_orientation = rotation.inverse(world_inertia_orientation)
  local local_x, local_y, local_z = rotation.rotate_vector(
    inverse_world_inertia_orientation,
    acceleration_x, acceleration_y, acceleration_z
  )
  return rotation.rotate_vector(
    world_inertia_orientation,
    local_x * inertia_x, local_y * inertia_y, local_z * inertia_z
  )
end

return PoseController
