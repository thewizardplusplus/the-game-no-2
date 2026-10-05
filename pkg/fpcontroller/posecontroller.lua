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
local utils = require("pkg.fpcontroller.utils")
local vectorutils = require("pkg.fpcontroller.utils.vector")
local quaternionutils = require("pkg.fpcontroller.utils.quaternion")
local colliderutils = require("pkg.fpcontroller.utils.collider")

local function _calculate_pd_acceleration(
  displacement_error,
  velocity_error,
  frequency,
  damping_ratio
)
  assertions.is_table(displacement_error)
  assertions.is_table(velocity_error)
  assertions.is_number(frequency)
  assertions.is_number(damping_ratio)

  local angular_frequency = (2 * math.pi) * frequency
  return angular_frequency ^ 2 * displacement_error
    + 2 * damping_ratio * angular_frequency * velocity_error
end

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
-- @tfield vector target_position target center-of-mass position (**read-only**)
-- @tfield quaternion target_orientation target orientation (**read-only**)
-- @tfield vector previous_target_position previous target used to derive velocity (**read-only**)
-- @tfield quaternion previous_target_orientation previous target orientation used to derive angular velocity (**read-only**)
-- @tfield number position_error latest center-of-mass position error magnitude (**read-only**)
-- @tfield number orientation_error latest orientation error magnitude, in radians (**read-only**)
-- @tfield vector last_force last applied force (**read-only**)
-- @tfield vector last_torque last applied torque (**read-only**)

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

  local target_position = colliderutils.get_center_of_mass(collider)
  local target_orientation = colliderutils.get_orientation(collider)

  self.collider = collider
  self.position_frequency = options.position_frequency
  self.position_damping = options.position_damping
  self.rotation_frequency = options.rotation_frequency
  self.rotation_damping = options.rotation_damping
  self.max_linear_speed = options.max_linear_speed
  self.max_angular_speed = options.max_angular_speed
  self.max_linear_acceleration = options.max_linear_acceleration
  self.max_angular_acceleration = options.max_angular_acceleration
  self.target_position = target_position
  self.target_orientation = target_orientation
  self.previous_target_position = target_position
  self.previous_target_orientation = target_orientation
  self.position_error = 0
  self.orientation_error = 0
  self.last_force = vector.zero
  self.last_torque = vector.zero
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
-- @treturn vector last applied force
function PoseController:get_applied_force()
  return self.last_force
end

---
-- @treturn vector last applied torque
function PoseController:get_applied_torque()
  return self.last_torque
end

---
-- ⚠️. Apply bounded force and torque towards the target pose.
-- @tparam number dt frame duration
function PoseController:pre_physics_update(dt)
  assertions.is_number(dt)

  local velocity = vector(self.collider:getLinearVelocity())
  local target_velocity = vectorutils.limit_length(
    (self.target_position - self.previous_target_position) / dt,
    self.max_linear_speed
  )

  local position_error = self:_update_position_error()
  local velocity_error = target_velocity - velocity
  local acceleration = vectorutils.limit_length(
    _calculate_pd_acceleration(
      position_error,
      velocity_error,
      self.position_frequency,
      self.position_damping
    ),
    self.max_linear_acceleration
  )

  self.last_force = acceleration * self.collider:getMass()
  self.collider:applyForce(self.last_force)

  local target_orientation_delta =
    quaternionutils.difference(self.previous_target_orientation, self.target_orientation)
  local target_angular_velocity = vectorutils.limit_length(
    quaternionutils.to_rotation_vector(target_orientation_delta) / dt,
    self.max_angular_speed
  )

  local orientation, rotation_error = self:_update_orientation_error()
  local angular_velocity_error =
    target_angular_velocity - vector(self.collider:getAngularVelocity())
  local angular_acceleration = vectorutils.limit_length(
    _calculate_pd_acceleration(
      rotation_error,
      angular_velocity_error,
      self.rotation_frequency,
      self.rotation_damping
    ),
    self.max_angular_acceleration
  )

  self.last_torque = self:_get_world_torque(orientation, angular_acceleration)
  self.collider:applyTorque(self.last_torque)

  self.previous_target_position = self.target_position
  self.previous_target_orientation = self.target_orientation
end

---
-- ⚠️. Set the desired center-of-mass position and collider orientation.
-- @tparam vector position target center-of-mass position
-- @tparam quaternion orientation target orientation
function PoseController:set_target_pose(position, orientation)
  assertions.is_table(position)
  assertions.is_table(orientation)

  self.target_position = position
  self.target_orientation = orientation
end

function PoseController:_update_position_error()
  local position = colliderutils.get_center_of_mass(self.collider)
  local error = self.target_position - position
  self.position_error = error:length()

  return error
end

function PoseController:_update_orientation_error()
  local orientation = colliderutils.get_orientation(self.collider)
  local orientation_delta = quaternionutils.difference(orientation, self.target_orientation)
  local error = quaternionutils.to_rotation_vector(orientation_delta)
  self.orientation_error = error:length()

  return orientation, error
end

function PoseController:_get_world_torque(orientation, acceleration)
  assertions.is_table(orientation)
  assertions.is_table(acceleration)

  local inertia_x, inertia_y, inertia_z,
    inertia_angle, inertia_axis_x, inertia_axis_y, inertia_axis_z =
      self.collider:getInertia()
  local inertia_orientation =
    quaternion.angleaxis(inertia_angle, inertia_axis_x, inertia_axis_y, inertia_axis_z)
  local world_inertia_orientation = orientation * inertia_orientation
  local local_acceleration = world_inertia_orientation:conjugate() * acceleration
  local local_torque = local_acceleration * vector(inertia_x, inertia_y, inertia_z)
  return world_inertia_orientation * local_torque
end

return PoseController
