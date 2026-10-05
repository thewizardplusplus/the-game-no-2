local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local CarryController = require("pkg.fpcontroller.carrycontroller")
local _ENV = require("compat53.module")
if _VERSION == "Lua 5.1" then
  setfenv(1, _ENV)
end

-- MockCollider

local MockCollider = middleclass("MockCollider")

function MockCollider:initialize()
  self.tag = "dynamic"
  self.position = vector.zero
  self.center = vector.zero
  self.orientation = quaternion.identity
  self.velocity = vector.zero
  self.angular_velocity = vector.zero
  self.linear_damping, self.angular_damping = 0.05, 0.1
  self.gravity_scale = 1
  self.mass = 20
  self.inertia = vector.one
  self.linear_velocity_set_count, self.angular_velocity_set_count = 0, 0
end

-- MockCollider / Motion

function MockCollider:setPosition(position)
  assertions.is_table(position)

  self.position = position
end

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

function MockCollider:setLinearVelocity(velocity)
  assertions.is_table(velocity)

  self.velocity = velocity
  self.linear_velocity_set_count = self.linear_velocity_set_count + 1
end

function MockCollider:getAngularVelocity()
  return self.angular_velocity:unpack()
end

function MockCollider:setAngularVelocity(angular_velocity)
  assertions.is_table(angular_velocity)

  self.angular_velocity = angular_velocity
  self.angular_velocity_set_count = self.angular_velocity_set_count + 1
end

function MockCollider:applyForce(force)
  assertions.is_table(force)

  self.applied_force = force
end

function MockCollider:applyTorque(torque)
  assertions.is_table(torque)

  self.applied_torque = torque
end

function MockCollider:getLinearDamping()
  return self.linear_damping
end

function MockCollider:setLinearDamping(value)
  assertions.is_number(value)

  self.linear_damping = value
end

function MockCollider:getAngularDamping()
  return self.angular_damping
end

function MockCollider:setAngularDamping(value)
  assertions.is_number(value)

  self.angular_damping = value
end

function MockCollider:getGravityScale()
  return self.gravity_scale
end

function MockCollider:setGravityScale(value)
  assertions.is_number(value)

  self.gravity_scale = value
end

-- MockCollider / Collision

function MockCollider:getTag()
  return self.tag
end

function MockCollider:setTag(tag)
  assertions.is_string(tag)

  self.tag = tag
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

-- MockWorld

local MockWorld = middleclass("MockWorld")

function MockWorld:initialize()
  self.raycast_results = {}
  self.raycast_calls = {}
end

-- MockWorld / Queries

function MockWorld:raycast(start, finish, filter)
  assertions.is_table(start)
  assertions.is_table(finish)
  assertions.is_string(filter)

  table.insert(self.raycast_calls, {start, finish, filter})

  local result = self.raycast_results[#self.raycast_calls]
  if not result then
    return nil
  end

  return table.unpack(result, 1, 9)
end

-- MockCameraProvider

local MockCameraProvider = middleclass("MockCameraProvider")

function MockCameraProvider:initialize()
  self.position = vector(1, 2, 3)
  self.position_call_count = 0
end

function MockCameraProvider:get_camera_position()
  self.position_call_count = self.position_call_count + 1
  return self.position
end

-- MockCameraProvider / Direction

local MockDirectionCameraProvider = middleclass("MockDirectionCameraProvider", MockCameraProvider)

function MockDirectionCameraProvider:initialize()
  MockCameraProvider.initialize(self)

  self.direction = vector.forward
  self.direction_call_count = 0
end

function MockDirectionCameraProvider:get_camera_direction()
  self.direction_call_count = self.direction_call_count + 1
  return self.direction
end

-- MockCameraProvider / Orientation

local MockOrientationCameraProvider =
  middleclass("MockOrientationCameraProvider", MockCameraProvider)

function MockOrientationCameraProvider:initialize()
  MockCameraProvider.initialize(self)

  self.orientation = quaternion.lookdir(vector.forward)
  self.orientation_call_count = 0
end

function MockOrientationCameraProvider:get_camera_orientation()
  self.orientation_call_count = self.orientation_call_count + 1
  return self.orientation
end

-- utility functions

local function _hit(collider)
  assertions.is_instance(collider, MockCollider)

  return {collider, {}, 0, 0, 0, 0, 0, 1, 0}
end

local function _record_collider_changes()
  local changes = {}
  return changes, function(current_collider, previous_collider)
    assertions.is_table_or_nil(current_collider)
    assertions.is_table_or_nil(previous_collider)

    table.insert(changes, { current = current_collider, previous = previous_collider })
  end
end

-- luacheck: globals TestCarryController
TestCarryController = {}

-- TestCarryController / Constructor

function TestCarryController.test_constructor_with_default_options()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  luaunit.assert_equals(controller.world, world)
  luaunit.assert_equals(controller.camera_provider, camera_provider)
  luaunit.assert_equals(controller.interaction_distance, 2.5)
  luaunit.assert_equals(controller.maximum_carry_mass, math.huge)
  luaunit.assert_equals(controller.hold_offset, vector.forward)
  luaunit.assert_equals(controller.pull_speed, 6)
  luaunit.assert_equals(controller.held_linear_damping, 0.8)
  luaunit.assert_equals(controller.held_angular_damping, 0.95)
  luaunit.assert_equals(controller.break_distance, 0.75)
  luaunit.assert_equals(controller.break_duration, 0.25)
  luaunit.assert_equals(controller.interaction_filter, "~player ~trigger ~held")
  luaunit.assert_equals(controller.carryable_tag, "dynamic")
  luaunit.assert_equals(controller.held_tag, "held")
  luaunit.assert_equals(controller.pose_controller_options, {})
  luaunit.assert_is_function(controller.on_held_collider_changed)
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
  luaunit.assert_nil(controller.held_original_tag)
  luaunit.assert_nil(controller.held_original_linear_damping)
  luaunit.assert_nil(controller.held_original_angular_damping)
  luaunit.assert_nil(controller.held_original_gravity_scale)
  luaunit.assert_nil(controller.current_hold_offset)
  luaunit.assert_nil(controller.held_relative_orientation)
  luaunit.assert_equals(controller.break_timer, 0)
end

function TestCarryController.test_constructor_with_custom_options()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local pose_controller_options = { position_frequency = 2 }
  local callback = function() end
  local controller = CarryController:new(world, camera_provider, {
    interaction_distance = 3,
    maximum_carry_mass = 4,
    hold_offset = vector(6, 7, -5),
    pull_speed = 8,
    held_linear_damping = 0.1, held_angular_damping = 0.2,
    break_distance = 9, break_duration = 10,
    interaction_filter = "solid", carryable_tag = "carryable", held_tag = "carried",
    pose_controller_options = pose_controller_options,
    on_held_collider_changed = callback,
  })

  luaunit.assert_equals(controller.world, world)
  luaunit.assert_equals(controller.camera_provider, camera_provider)
  luaunit.assert_equals(controller.interaction_distance, 3)
  luaunit.assert_equals(controller.maximum_carry_mass, 4)
  luaunit.assert_equals(controller.hold_offset, vector(6, 7, -5))
  luaunit.assert_equals(controller.pull_speed, 8)
  luaunit.assert_equals(controller.held_linear_damping, 0.1)
  luaunit.assert_equals(controller.held_angular_damping, 0.2)
  luaunit.assert_equals(controller.break_distance, 9)
  luaunit.assert_equals(controller.break_duration, 10)
  luaunit.assert_equals(controller.interaction_filter, "solid")
  luaunit.assert_equals(controller.carryable_tag, "carryable")
  luaunit.assert_equals(controller.held_tag, "carried")
  luaunit.assert_equals(controller.pose_controller_options, pose_controller_options)
  luaunit.assert_not_is(controller.pose_controller_options, pose_controller_options)
  luaunit.assert_equals(controller.on_held_collider_changed, callback)
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
  luaunit.assert_nil(controller.held_original_tag)
  luaunit.assert_nil(controller.held_original_linear_damping)
  luaunit.assert_nil(controller.held_original_angular_damping)
  luaunit.assert_nil(controller.held_original_gravity_scale)
  luaunit.assert_nil(controller.current_hold_offset)
  luaunit.assert_nil(controller.held_relative_orientation)
  luaunit.assert_equals(controller.break_timer, 0)
end

-- TestCarryController / Acquisition and release

function TestCarryController.test_acquire_holds_first_visible_carryable_collider()
  local collider = MockCollider:new()
  collider:setPosition(vector(1.25, 2, 1.5))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local changes, callback = _record_collider_changes()
  local controller = CarryController:new(world, camera_provider, {
    interaction_distance = 3,
    maximum_carry_mass = 20,
    held_linear_damping = 0.2, held_angular_damping = 0.3,
    pose_controller_options = { position_frequency = 2 },
    on_held_collider_changed = callback,
  })

  local is_held = controller:acquire()
  luaunit.assert_true(is_held)

  luaunit.assert_equals(world.raycast_calls, {
    {vector(1, 2, 3), vector(1, 2, 0), "~player ~trigger ~held"},
  })
  luaunit.assert_equals(collider.tag, "held")
  luaunit.assert_equals(collider.linear_damping, 0.2)
  luaunit.assert_equals(collider.angular_damping, 0.3)
  luaunit.assert_equals(collider.gravity_scale, 0)
  luaunit.assert_equals(changes, {{ current = collider }})
  luaunit.assert_equals(controller.held_collider, collider)
  luaunit.assert_equals(controller.pose_controller.collider, collider)
  luaunit.assert_equals(controller.pose_controller.position_frequency, 2)
  luaunit.assert_equals(controller.held_original_tag, "dynamic")
  luaunit.assert_equals(controller.held_original_linear_damping, 0.05)
  luaunit.assert_equals(controller.held_original_angular_damping, 0.1)
  luaunit.assert_equals(controller.held_original_gravity_scale, 1)
  luaunit.assert_equals(controller.current_hold_offset, vector(0.25, 0, -1.5))
  luaunit.assert_equals(controller.held_relative_orientation, quaternion.identity)
  luaunit.assert_equals(controller.break_timer, 0)
end

function TestCarryController.test_acquire_does_nothing_while_collider_is_held()
  local collider = MockCollider:new()
  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local changes, callback = _record_collider_changes()
  local controller = CarryController:new(world, camera_provider, {
    on_held_collider_changed = callback,
  })

  controller:acquire()

  local is_held = controller:acquire()
  luaunit.assert_true(is_held)

  luaunit.assert_equals(#world.raycast_calls, 1)
  luaunit.assert_equals(changes, {{ current = collider }})
  luaunit.assert_equals(controller.held_collider, collider)
end

function TestCarryController.test_acquire_returns_false_when_raycast_misses()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  local is_held = controller:acquire()
  luaunit.assert_false(is_held)

  luaunit.assert_equals(#world.raycast_calls, 1)
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
end

function TestCarryController.test_acquire_rejects_near_zero_camera_direction()
  local camera_provider = MockDirectionCameraProvider:new()
  camera_provider.direction = vector(0.5e-9, 0, 0)

  local world = MockWorld:new()
  local controller = CarryController:new(world, camera_provider)

  luaunit.assert_error_msg_contains(
    "camera direction must be nonzero",
    function()
      controller:acquire()
    end
  )
  luaunit.assert_equals(#world.raycast_calls, 0)
end

function TestCarryController.test_acquire_rejects_non_carryable_occluder()
  local collider = MockCollider:new()
  collider.tag = "environment"

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  local is_held = controller:acquire()
  luaunit.assert_false(is_held)

  luaunit.assert_equals(collider.tag, "environment")
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
end

function TestCarryController.test_acquire_rejects_collider_above_maximum_mass()
  local collider = MockCollider:new()
  collider.mass = 21

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, { maximum_carry_mass = 20 })

  local is_held = controller:acquire()
  luaunit.assert_false(is_held)

  luaunit.assert_equals(collider.tag, "dynamic")
  luaunit.assert_equals(collider.linear_damping, 0.05)
  luaunit.assert_equals(collider.angular_damping, 0.1)
  luaunit.assert_equals(collider.gravity_scale, 1)
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
end

function TestCarryController.test_release_restores_collider_and_clears_holding_state()
  local collider = MockCollider:new()
  collider.linear_damping, collider.angular_damping, collider.gravity_scale = 0.2, 0.3, 0.4

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local changes, callback = _record_collider_changes()
  local controller = CarryController:new(world, camera_provider, {
    on_held_collider_changed = callback,
  })

  controller:acquire()

  controller.break_timer = 0.1
  controller:release()

  luaunit.assert_equals(collider.tag, "dynamic")
  luaunit.assert_equals(collider.linear_damping, 0.2)
  luaunit.assert_equals(collider.angular_damping, 0.3)
  luaunit.assert_equals(collider.gravity_scale, 0.4)
  luaunit.assert_equals(collider.linear_velocity_set_count, 0)
  luaunit.assert_equals(collider.angular_velocity_set_count, 0)
  luaunit.assert_equals(changes, {{ current = collider }, { previous = collider }})
  luaunit.assert_nil(controller.held_collider)
  luaunit.assert_nil(controller.pose_controller)
  luaunit.assert_nil(controller.held_original_tag)
  luaunit.assert_nil(controller.held_original_linear_damping)
  luaunit.assert_nil(controller.held_original_angular_damping)
  luaunit.assert_nil(controller.held_original_gravity_scale)
  luaunit.assert_nil(controller.current_hold_offset)
  luaunit.assert_nil(controller.held_relative_orientation)
  luaunit.assert_equals(controller.break_timer, 0)
end

function TestCarryController.test_release_does_nothing_without_held_collider()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local changes, callback = _record_collider_changes()
  local controller = CarryController:new(world, camera_provider, {
    on_held_collider_changed = callback,
  })

  controller:release()

  luaunit.assert_equals(changes, {})
  luaunit.assert_nil(controller.held_collider)
end

function TestCarryController.test_toggle_acquires_then_releases_collider()
  local collider = MockCollider:new()
  local world = MockWorld:new()
  world.raycast_results = {_hit(collider), _hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  luaunit.assert_true(controller:toggle())
  luaunit.assert_equals(controller.held_collider, collider)

  luaunit.assert_false(controller:toggle())
  luaunit.assert_nil(controller.held_collider)

  luaunit.assert_true(controller:toggle())
  luaunit.assert_equals(controller.held_collider, collider)

  luaunit.assert_false(controller:toggle())
  luaunit.assert_nil(controller.held_collider)
end

-- TestCarryController / Pre-physics update

function TestCarryController.test_pre_physics_update_does_nothing_without_held_collider()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  controller:pre_physics_update(0.1)

  luaunit.assert_equals(camera_provider.position_call_count, 0)
  luaunit.assert_equals(camera_provider.direction_call_count, 0)
end

function TestCarryController.test_pre_physics_update_sets_camera_local_target_pose()
  local collider = MockCollider:new()
  collider:setPosition(vector(2, 2, 3))
  collider.orientation = quaternion.angleaxis(0.4, 0, 1, 0)

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockOrientationCameraProvider:new()
  camera_provider.orientation = quaternion.lookdir(vector.right)

  local controller = CarryController:new(world, camera_provider, {
    hold_offset = vector(0.25, -0.5, -1),
  })

  controller:acquire()

  camera_provider.orientation = quaternion.lookdir(vector.forward)
  controller:pre_physics_update(0.25)

  luaunit.assert_equals(camera_provider.position_call_count, 2)
  luaunit.assert_equals(camera_provider.orientation_call_count, 2)

  luaunit.assert_equals(controller.pose_controller.target_position, vector(1.25, 1.5, 2))

  local angle, axis_x, axis_y, axis_z =
    controller.pose_controller.target_orientation:toangleaxis()
  luaunit.assert_almost_equals(angle, math.pi / 2 + 0.4, 1e-9)
  luaunit.assert_almost_equals(axis_x, 0, 1e-9)
  luaunit.assert_almost_equals(axis_y, 1, 1e-9)
  luaunit.assert_almost_equals(axis_z, 0, 1e-9)
end

function TestCarryController.test_pre_physics_update_uses_direction_camera_provider()
  local collider = MockCollider:new()
  collider:setPosition(vector(1, 2, 2))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, {
    hold_offset = vector(0, 0, -0.75),
  })

  controller:acquire()
  controller:pre_physics_update(0.25)

  luaunit.assert_true(collider.applied_force.z > 0)
  luaunit.assert_equals(camera_provider.direction_call_count, 2)
  luaunit.assert_equals(controller.pose_controller.target_position, vector(1, 2, 2.25))
end

function TestCarryController.test_pre_physics_update_limits_outward_pull_speed()
  local collider = MockCollider:new()
  collider:setPosition(vector(1, 2, 2.5))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, {
    hold_offset = vector.forward,
    pull_speed = 1,
  })

  controller:acquire()
  controller:pre_physics_update(0.1)

  luaunit.assert_equals(controller.current_hold_offset, vector(0, 0, -0.6))
  luaunit.assert_almost_equals(controller.pose_controller.target_position.z, 2.4, 1e-9)
end

function TestCarryController.test_pre_physics_update_limits_inward_pull_speed()
  local collider = MockCollider:new()
  collider:setPosition(vector(1, 2, 1))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, {
    hold_offset = vector.forward,
    pull_speed = 2,
  })

  controller:acquire()
  controller:pre_physics_update(0.25)

  luaunit.assert_equals(controller.current_hold_offset, vector(0, 0, -1.5))
  luaunit.assert_almost_equals(controller.pose_controller.target_position.z, 1.5, 1e-9)
end

function TestCarryController.test_pre_physics_update_limits_diagonal_pull_speed()
  local collider = MockCollider:new()
  collider:setPosition(vector(1, 2, 2))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, {
    hold_offset = vector(3, 4, -1),
    pull_speed = 1,
  })

  controller:acquire()
  controller:pre_physics_update(1)

  luaunit.assert_almost_equals(controller.current_hold_offset.x, 0.6, 1e-9)
  luaunit.assert_almost_equals(controller.current_hold_offset.y, 0.8, 1e-9)
  luaunit.assert_almost_equals(controller.current_hold_offset.z, -1, 1e-9)
  luaunit.assert_almost_equals(controller.pose_controller.target_position.x, 1.6, 1e-9)
  luaunit.assert_almost_equals(controller.pose_controller.target_position.y, 2.8, 1e-9)
  luaunit.assert_almost_equals(controller.pose_controller.target_position.z, 2, 1e-9)
end

-- TestCarryController / Post-physics update

function TestCarryController.test_post_physics_update_does_nothing_without_held_collider()
  local world = MockWorld:new()
  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider)

  controller:post_physics_update(0.1)

  luaunit.assert_equals(controller.break_timer, 0)
end

function TestCarryController.test_post_physics_update_resets_timer_when_error_is_acceptable()
  local collider = MockCollider:new()
  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local controller = CarryController:new(world, camera_provider, { break_distance = 0.1 })

  controller:acquire()

  controller.break_timer = 0.2
  controller:post_physics_update(0.1)

  luaunit.assert_equals(controller.break_timer, 0)
  luaunit.assert_equals(controller.held_collider, collider)
end

function TestCarryController.test_post_physics_update_releases_after_sustained_excessive_error()
  local collider = MockCollider:new()
  collider:setPosition(vector(1, 2, 2))

  local world = MockWorld:new()
  world.raycast_results = {_hit(collider)}

  local camera_provider = MockDirectionCameraProvider:new()
  local changes, callback = _record_collider_changes()
  local controller = CarryController:new(world, camera_provider, {
    break_distance = 0.1, break_duration = 0.2,
    on_held_collider_changed = callback,
  })

  controller:acquire()
  controller:pre_physics_update(0.1)

  collider.position = vector(2, 0, 0)
  controller:post_physics_update(0.1)
  luaunit.assert_equals(controller.break_timer, 0.1)
  luaunit.assert_equals(controller.held_collider, collider)

  controller:post_physics_update(0.1)
  luaunit.assert_equals(collider.tag, "dynamic")
  luaunit.assert_equals(changes, {{ current = collider }, { previous = collider }})
  luaunit.assert_nil(controller.held_collider)
end
