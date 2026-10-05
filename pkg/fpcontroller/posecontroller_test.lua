local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local PoseController = require("pkg.fpcontroller.posecontroller")

-- MockCollider

local MockCollider = middleclass("MockCollider")

function MockCollider:initialize()
  self.position = vector.zero
  self.center = vector.zero
  self.orientation = quaternion.identity
  self.velocity = vector.zero
  self.angular_velocity = vector.zero
  self.mass = 2
  self.inertia = vector(2, 2, 2)
end

-- MockCollider / Motion

function MockCollider:getOrientation()
  return self.orientation:toangleaxis()
end

function MockCollider:getWorldPoint(point)
  assertions.is_table(point)

  return (self.position + point):unpack()
end

function MockCollider:getLinearVelocity()
  return self.velocity:unpack()
end

function MockCollider:getAngularVelocity()
  return self.angular_velocity:unpack()
end

function MockCollider:applyForce(force)
  assertions.is_table(force)

  self.applied_force = force
end

function MockCollider:applyTorque(torque)
  assertions.is_table(torque)

  self.applied_torque = torque
end

-- MockCollider / Mass

function MockCollider:getMass()
  return self.mass
end

function MockCollider:getInertia()
  return self.inertia.x, self.inertia.y, self.inertia.z, 0, 0, 1, 0
end

function MockCollider:getCenterOfMass()
  return self.center:unpack()
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
  luaunit.assert_equals(controller.target_position, vector.zero)
  luaunit.assert_equals(controller.target_orientation, quaternion.identity)
  luaunit.assert_equals(controller.previous_target_position, vector.zero)
  luaunit.assert_equals(controller.previous_target_orientation, quaternion.identity)
  luaunit.assert_equals(controller.position_error, 0)
  luaunit.assert_equals(controller.orientation_error, 0)
  luaunit.assert_equals(controller:get_applied_force(), vector.zero)
  luaunit.assert_equals(controller:get_applied_torque(), vector.zero)
end

function TestPoseController.test_constructor_with_custom_options()
  local collider = MockCollider:new()
  collider.position = vector(1, 2, 3)
  collider.center = vector(4, 5, 6)
  collider.orientation = quaternion.angleaxis(math.pi / 2, 0, 1, 0)

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
  luaunit.assert_equals(controller.target_position, vector(5, 7, 9))
  luaunit.assert_equals(controller.target_orientation, quaternion.angleaxis(math.pi / 2, 0, 1, 0))
  luaunit.assert_equals(controller.previous_target_position, vector(5, 7, 9))
  luaunit.assert_equals(controller.previous_target_orientation, controller.target_orientation)
  luaunit.assert_equals(controller.position_error, 0)
  luaunit.assert_equals(controller.orientation_error, 0)
  luaunit.assert_equals(controller:get_applied_force(), vector.zero)
  luaunit.assert_equals(controller:get_applied_torque(), vector.zero)
end

function TestPoseController.test_get_position_error()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(vector(2, 3, 6), quaternion.identity)

  luaunit.assert_equals(controller:get_position_error(), 7)
end

function TestPoseController.test_get_orientation_error()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(vector.zero, quaternion.angleaxis(math.pi / 3, 0, 0, 1))

  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 3, 1e-9)
end

function TestPoseController.test_get_applied_force_and_torque()
  local controller = PoseController:new(MockCollider:new())

  luaunit.assert_equals(controller:get_applied_force(), vector.zero)
  luaunit.assert_equals(controller:get_applied_torque(), vector.zero)
end

function TestPoseController.test_pre_physics_update_applies_bounded_position_force()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider)
  controller:set_target_pose(vector.right, quaternion.identity)

  controller:pre_physics_update(1)

  luaunit.assert_equals(collider.applied_force, vector(120, 0, 0))
  luaunit.assert_almost_equals(controller:get_position_error(), 1, 1e-9)
  luaunit.assert_equals(controller:get_applied_force(), collider.applied_force)
end

function TestPoseController.test_pre_physics_update_damps_linear_velocity()
  local collider = MockCollider:new()
  collider.velocity = vector.right

  local controller = PoseController:new(collider, {
    position_frequency = 1,
    max_linear_acceleration = 100,
  })

  controller:pre_physics_update(1)

  luaunit.assert_almost_equals(collider.applied_force.x, -8 * math.pi, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force.y, 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_force.z, 0, 1e-9)
end

function TestPoseController.test_pre_physics_update_keeps_zero_rotation_torque_finite()
  local collider = MockCollider:new()
  collider.orientation = quaternion.lookdir(vector(0, -1, -0.01))

  local controller = PoseController:new(collider)

  controller:pre_physics_update(1 / 120)

  luaunit.assert_equals(collider.applied_torque, vector.zero)
end

function TestPoseController.test_pre_physics_update_applies_orientation_torque()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider, {
    rotation_frequency = 1, rotation_damping = 0,
    max_angular_acceleration = 100,
  })
  controller:set_target_pose(vector.zero, quaternion.angleaxis(math.pi / 2, 0, 0, 1))

  controller:pre_physics_update(1)

  local expected_torque = 2 * (2 * math.pi) ^ 2 * math.pi / 2
  luaunit.assert_almost_equals(collider.applied_torque.x, 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_torque.y, 0, 1e-9)
  luaunit.assert_almost_equals(collider.applied_torque.z, expected_torque, 1e-9)
  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 2, 1e-9)
  luaunit.assert_equals(controller:get_applied_torque(), collider.applied_torque)
end

function TestPoseController.test_pre_physics_update_uses_shortest_orientation_path()
  local collider = MockCollider:new()
  local controller = PoseController:new(collider, {
    rotation_frequency = 1, rotation_damping = 0,
    max_angular_acceleration = 100,
  })
  controller:set_target_pose(vector.zero, quaternion.angleaxis(3 * math.pi / 2, 0, 0, 1))

  controller:pre_physics_update(1)

  luaunit.assert_true(collider.applied_torque.z < 0)
  luaunit.assert_almost_equals(controller:get_orientation_error(), math.pi / 2, 1e-9)
end

function TestPoseController.test_set_target_pose()
  local controller = PoseController:new(MockCollider:new())

  controller:set_target_pose(vector(1, 2, 3), quaternion.angleaxis(math.pi / 2, 1, 0, 0))

  luaunit.assert_equals(controller.target_position, vector(1, 2, 3))
  luaunit.assert_equals(
    controller.target_orientation,
    quaternion.angleaxis(math.pi / 2, 1, 0, 0)
  )
end
