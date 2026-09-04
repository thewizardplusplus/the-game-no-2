local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local PoseController = require("pkg.fpcontroller.posecontroller")
local rotation = require("pkg.fpcontroller.utils.rotation")

-- MockCollider

local MockCollider = middleclass("MockCollider")

function MockCollider:initialize()
  self.x, self.y, self.z = 0, 0, 0
  self.center_x, self.center_y, self.center_z = 0, 0, 0
  self.angle, self.axis_x, self.axis_y, self.axis_z = 0, 0, 1, 0
  self.velocity_x, self.velocity_y, self.velocity_z = 0, 0, 0
  self.angular_velocity_x, self.angular_velocity_y, self.angular_velocity_z = 0, 0, 0
  self.mass = 2
  self.inertia_x, self.inertia_y, self.inertia_z = 2, 2, 2
end

-- MockCollider / Motion

function MockCollider:getOrientation()
  return self.angle, self.axis_x, self.axis_y, self.axis_z
end

function MockCollider:getWorldPoint(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  return self.x + x, self.y + y, self.z + z
end

function MockCollider:getLinearVelocity()
  return self.velocity_x, self.velocity_y, self.velocity_z
end

function MockCollider:getAngularVelocity()
  return self.angular_velocity_x, self.angular_velocity_y, self.angular_velocity_z
end

function MockCollider:applyForce(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  self.applied_force = {x, y, z}
end

function MockCollider:applyTorque(x, y, z)
  assertions.is_number(x)
  assertions.is_number(y)
  assertions.is_number(z)

  self.applied_torque = {x, y, z}
end

-- MockCollider / Mass

function MockCollider:getMass()
  return self.mass
end

function MockCollider:getInertia()
  return self.inertia_x, self.inertia_y, self.inertia_z, 0, 0, 1, 0
end

function MockCollider:getCenterOfMass()
  return self.center_x, self.center_y, self.center_z
end

-- luacheck: globals TestPoseController
TestPoseController = {}

function TestPoseController.test_constructor_with_default_options()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)

  luaunit.assert_equals(controller.collider, collider)
  luaunit.assert_equals(controller.position_frequency, 5)
  luaunit.assert_equals(controller.position_damping, 1)
  luaunit.assert_equals(controller.rotation_frequency, 4)
  luaunit.assert_equals(controller.rotation_damping, 1)
  luaunit.assert_equals(controller.max_linear_speed, 8)
  luaunit.assert_almost_equals(controller.max_angular_speed, 4 * math.pi, 1e-9)
  luaunit.assert_equals(controller.max_linear_acceleration, 60)
  luaunit.assert_almost_equals(controller.max_angular_acceleration, 16 * math.pi, 1e-9)
  luaunit.assert_equals({controller.target_x, controller.target_y, controller.target_z}, {0, 0, 0})
  luaunit.assert_equals(controller.target_orientation, {1, 0, 0, 0})
  luaunit.assert_equals(
    {controller.previous_target_x, controller.previous_target_y, controller.previous_target_z},
    {0, 0, 0}
  )
  luaunit.assert_equals(controller.previous_target_orientation, {1, 0, 0, 0})
  luaunit.assert_equals(controller.position_error, 0)
  luaunit.assert_equals(controller.orientation_error, 0)
  luaunit.assert_equals({controller:get_applied_force()}, {0, 0, 0})
  luaunit.assert_equals({controller:get_applied_torque()}, {0, 0, 0})
end

function TestPoseController.test_constructor_with_custom_options()
  local collider = MockCollider:new()
  collider.x, collider.y, collider.z = 1, 2, 3
  collider.center_x, collider.center_y, collider.center_z = 4, 5, 6
  collider.angle, collider.axis_x, collider.axis_y, collider.axis_z = math.pi / 2, 0, 1, 0

  local controller = PoseController:new(collider, {
    position_frequency = 1, position_damping = 2,
    rotation_frequency = 3, rotation_damping = 4,
    max_linear_speed = 5, max_angular_speed = 6,
    max_linear_acceleration = 7, max_angular_acceleration = 8,
  })

  luaunit.assert_equals(controller.collider, collider)
  luaunit.assert_equals(controller.position_frequency, 1)
  luaunit.assert_equals(controller.position_damping, 2)
  luaunit.assert_equals(controller.rotation_frequency, 3)
  luaunit.assert_equals(controller.rotation_damping, 4)
  luaunit.assert_equals(controller.max_linear_speed, 5)
  luaunit.assert_equals(controller.max_angular_speed, 6)
  luaunit.assert_equals(controller.max_linear_acceleration, 7)
  luaunit.assert_equals(controller.max_angular_acceleration, 8)
  luaunit.assert_equals({controller.target_x, controller.target_y, controller.target_z}, {5, 7, 9})
  luaunit.assert_equals(
    controller.target_orientation,
    rotation.from_angle_and_axis(math.pi / 2, 0, 1, 0)
  )
  luaunit.assert_equals(
    {controller.previous_target_x, controller.previous_target_y, controller.previous_target_z},
    {5, 7, 9}
  )
  luaunit.assert_equals(controller.previous_target_orientation, controller.target_orientation)
  luaunit.assert_equals(controller.position_error, 0)
  luaunit.assert_equals(controller.orientation_error, 0)
  luaunit.assert_equals({controller:get_applied_force()}, {0, 0, 0})
  luaunit.assert_equals({controller:get_applied_torque()}, {0, 0, 0})
end

function TestPoseController.test_get_position_error()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(2, 3, 6, 0, 0, 1, 0)

  luaunit.assert_equals(controller:get_position_error(), 7)
end

function TestPoseController.test_get_orientation_error()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(0, 0, 0, math.pi / 3, 0, 0, 1)

  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 3, 1e-9)
end

function TestPoseController.test_get_applied_force_and_torque()
  local controller = PoseController:new(MockCollider:new())

  luaunit.assert_equals({controller:get_applied_force()}, {0, 0, 0})
  luaunit.assert_equals({controller:get_applied_torque()}, {0, 0, 0})
end

function TestPoseController.test_pre_physics_update_applies_bounded_position_force()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(1, 0, 0, 0, 0, 1, 0)

  controller:pre_physics_update(1)

  luaunit.assert_almost_equals(collider.applied_force[1], 120, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force[2], 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force[3], 0, 1e-9)
  luaunit.assert_almost_equals(controller:get_position_error(), 1, 1e-9)
  luaunit.assert_equals({controller:get_applied_force()}, collider.applied_force)
end

function TestPoseController.test_pre_physics_update_damps_linear_velocity()
  local collider = MockCollider:new()
  collider.velocity_x = 1

  local controller = PoseController:new(collider, {
    position_frequency = 1,
    max_linear_acceleration = 100,
  })

  controller:pre_physics_update(1)

  luaunit.assert_almost_equals(collider.applied_force[1], -8 * math.pi, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force[2], 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force[3], 0, 1e-9)
end

function TestPoseController.test_pre_physics_update_applies_orientation_torque()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider, {
    rotation_frequency = 1, rotation_damping = 0,
    max_angular_acceleration = 100,
  })
  controller:set_target_pose(0, 0, 0, math.pi / 2, 0, 0, 1)

  controller:pre_physics_update(1)

  local expected_torque = 2 * (2 * math.pi) ^ 2 * math.pi / 2
  luaunit.assert_almost_equals(collider.applied_torque[1], 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_torque[2], 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_torque[3], expected_torque, 1e-9)
  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 2, 1e-9)
  luaunit.assert_equals({controller:get_applied_torque()}, collider.applied_torque)
end

function TestPoseController.test_pre_physics_update_uses_shortest_orientation_path()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider, {
    rotation_frequency = 1, rotation_damping = 0,
    max_angular_acceleration = 100,
  })
  controller:set_target_pose(0, 0, 0, 3 * math.pi / 2, 0, 0, 1)

  controller:pre_physics_update(1)

  luaunit.assert_true(collider.applied_torque[3] < 0)
  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 2, 1e-9)
end

function TestPoseController.test_set_target_pose()
  local controller = PoseController:new(MockCollider:new())

  controller:set_target_pose(1, 2, 3, math.pi / 2, 1, 0, 0)

  luaunit.assert_equals({controller.target_x, controller.target_y, controller.target_z}, {1, 2, 3})
  luaunit.assert_equals(
    controller.target_orientation,
    rotation.from_angle_and_axis(math.pi / 2, 1, 0, 0)
  )
end
