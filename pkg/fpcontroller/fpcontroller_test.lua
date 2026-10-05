local luaunit = require("luaunit")
local middleclass = require("middleclass")
local assertions = require("luatypechecks.assertions")
local FPController = require("pkg.fpcontroller.fpcontroller")
local utils = require("pkg.fpcontroller.utils")
local _ENV = require("compat53.module")
if _VERSION == "Lua 5.1" then
  setfenv(1, _ENV)
end

-- MockShape

local MockShape = middleclass("MockShape")

function MockShape:setOffset(position, orientation)
  assertions.is_table(position)
  assertions.is_table(orientation)

  self.offset_position = position
  self.offset_orientation = orientation
end

-- MockCollider

local MockCollider = middleclass("MockCollider")

function MockCollider:initialize()
  self.position = vector.zero
  self.velocity = vector.zero
  self.surface_velocity = vector.zero
  self.applied_forces = {}
  self.shape = MockShape:new()
end

-- MockCollider / Motion

function MockCollider:getPosition()
  return self.position:unpack()
end

function MockCollider:setPosition(position)
  assertions.is_table(position)

  self.position = position
end

function MockCollider:getLinearVelocity()
  return self.velocity:unpack()
end

function MockCollider:setLinearVelocity(velocity)
  assertions.is_table(velocity)

  self.velocity = velocity
end

function MockCollider:getLinearVelocityFromWorldPoint(point)
  assertions.is_table(point)

  self.velocity_point = point
  return self.surface_velocity:unpack()
end

function MockCollider:applyForce(force)
  assertions.is_table(force)

  self.force = force
  table.insert(self.applied_forces, force)
end

function MockCollider:setContinuous(value)
  assertions.is_boolean(value)

  self.continuous = value
end

function MockCollider:setDegreesOfFreedom(translation, rotation) -- luacheck: no redefined
  assertions.is_string(translation)
  assertions.is_string(rotation)

  self.degrees_of_freedom = {translation, rotation}
end

function MockCollider:setSleepingAllowed(value)
  assertions.is_boolean(value)

  self.sleeping_allowed = value
end

-- MockCollider / Collision

function MockCollider:setTag(value)
  assertions.is_string(value)

  self.tag = value
end

function MockCollider:getShape()
  return self.shape
end

function MockCollider:setFriction(value)
  assertions.is_number(value)

  self.friction = value
end

function MockCollider:setRestitution(value)
  assertions.is_number(value)

  self.restitution = value
end

-- MockCollider / Mass

function MockCollider:setMass(value)
  assertions.is_number(value)

  self.configured_mass = value
end

-- MockWorld

local MockWorld = middleclass("MockWorld")

function MockWorld:initialize(collider)
  assertions.is_instance(collider, MockCollider)

  self.collider = collider
  self.raycast_results = {}
  self.raycast_calls = {}
  self.shapecast_results = {}
  self.shapecast_calls = {}
  self.overlap_results = {}
  self.overlap_calls = {}
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

function MockWorld:shapecast(
  shape,
  start,
  finish,
  orientation,
  filter
)
  assertions.is_instance(shape, MockShape)
  assertions.is_table(start)
  assertions.is_table(finish)
  assertions.is_table(orientation)
  assertions.is_string(filter)

  table.insert(self.shapecast_calls, {shape, start, finish, orientation, filter})

  local result = self.shapecast_results[#self.shapecast_calls]
  if not result then
    return nil
  end

  return table.unpack(result, 1, 10)
end

function MockWorld:overlapShape(
  shape,
  position,
  orientation,
  maximum_distance,
  filter
)
  assertions.is_instance(shape, MockShape)
  assertions.is_table(position)
  assertions.is_table(orientation)
  assertions.is_number(maximum_distance)
  assertions.is_string(filter)

  table.insert(self.overlap_calls, {shape, position, orientation, maximum_distance, filter})

  local result = self.overlap_results[#self.overlap_calls]
  if not result then
    return nil
  end

  return result
end

-- MockWorld / Colliders

function MockWorld:newCapsuleCollider(position, radius, length)
  assertions.is_table(position)
  assertions.is_number(radius)
  assertions.is_number(length)

  self.new_capsule_collider_arguments = {position, radius, length}

  self.collider:setPosition(position)
  self.collider.radius, self.collider.length = radius, length

  return self.collider
end

-- mock physics query results

local function _ground_hit(options)
  assertions.is_table_or_nil(options)

  options = utils.shallow_copy(options or {})
  options.collider = options.collider or {}
  options.shape = options.shape or {}
  options.position = options.position or vector.zero
  options.normal = options.normal or vector.up
  options.triangle = options.triangle or 0

  assertions.is_table(options.collider)
  assertions.is_table(options.shape)
  assertions.is_table(options.position)
  assertions.is_table(options.normal)
  assertions.is_number(options.triangle)

  return {
    options.collider, options.shape,
    options.position.x, options.position.y, options.position.z,
    options.normal.x, options.normal.y, options.normal.z,
    options.triangle,
  }
end

local function _dynamic_hit(collider, options)
  assertions.is_instance(collider, MockCollider)
  assertions.is_table_or_nil(options)

  options = utils.shallow_copy(options or {})
  options.shape = options.shape or {}
  options.position = options.position or vector.zero
  options.normal = options.normal or vector.backward
  options.fraction = options.fraction or 0
  options.triangle = options.triangle or 0

  assertions.is_table(options.shape)
  assertions.is_table(options.position)
  assertions.is_table(options.normal)
  assertions.is_number(options.fraction)
  assertions.is_number(options.triangle)

  return {
    collider, options.shape,
    options.position.x, options.position.y, options.position.z,
    options.normal.x, options.normal.y, options.normal.z,
    options.fraction,
    options.triangle,
  }
end

-- luacheck: globals TestFPController
TestFPController = {}

function TestFPController:setUp()
  self.original_lovr = rawget(_G, "lovr")
end

function TestFPController:tearDown()
  _G.lovr = self.original_lovr
end

-- TestFPController / Constructor

function TestFPController.test_constructor_with_default_options()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  local controller = FPController:new(world)

  luaunit.assert_equals({collider:getPosition()}, {0, 0, 0})
  luaunit.assert_equals(collider.radius, 0.3)
  luaunit.assert_almost_equals(collider.length, 1.2)
  luaunit.assert_equals(collider.shape.offset_position, vector.zero)
  luaunit.assert_equals(
    collider.shape.offset_orientation,
    quaternion.angleaxis(math.pi / 2, 1, 0, 0)
  )
  luaunit.assert_equals(collider.tag, "player")
  luaunit.assert_equals(collider.configured_mass, 75)
  luaunit.assert_equals(collider.friction, 0)
  luaunit.assert_equals(collider.restitution, 0)
  luaunit.assert_true(collider.continuous)
  luaunit.assert_false(collider.sleeping_allowed)
  luaunit.assert_equals(collider.degrees_of_freedom, {"xyz", ""})

  luaunit.assert_equals(world.new_capsule_collider_arguments[1], vector.zero)
  luaunit.assert_equals(world.new_capsule_collider_arguments[2], 0.3)
  luaunit.assert_almost_equals(world.new_capsule_collider_arguments[3], 1.2)

  luaunit.assert_equals(controller.world, world)
  luaunit.assert_equals(controller.yaw, 0)
  luaunit.assert_equals(controller.pitch, 0)
  luaunit.assert_almost_equals(controller.max_pitch, math.rad(89))
  luaunit.assert_equals(controller.mouse_sensitivity, 0.0025)
  luaunit.assert_false(controller.mouse_y_inverted)
  luaunit.assert_equals(controller.radius, 0.3)
  luaunit.assert_equals(controller.height, 1.8)
  luaunit.assert_equals(controller.eye_height, 1.65)
  luaunit.assert_equals(controller.mass, 75)
  luaunit.assert_equals(controller.speed, 2.5)
  luaunit.assert_equals(controller.speed_scale, 1)
  luaunit.assert_equals(controller.max_acceleration, 12)
  luaunit.assert_equals(controller.max_push_force, 350)
  luaunit.assert_almost_equals(controller.max_floor_angle, math.rad(5))
  luaunit.assert_equals(controller.max_step_height, 0.25)
  luaunit.assert_equals(controller.step_search_distance, 0.08)
  luaunit.assert_equals(controller.ground_tolerance, 0.08)
  luaunit.assert_equals(controller.contact_tolerance, 0.01)
  luaunit.assert_equals(controller.push_limit_filter, "dynamic")
  luaunit.assert_equals(controller.ground_filter, "~player ~trigger ~held")
  luaunit.assert_equals(controller.step_filter, "environment")
  luaunit.assert_equals(controller.obstruction_filter, "~player ~trigger ~held")
  luaunit.assert_equals(controller.collider, collider)
  luaunit.assert_nil(controller.ground_collider)
  luaunit.assert_nil(controller.ground_shape)
end

function TestFPController.test_constructor_with_custom_options()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  local controller = FPController:new(world, {
    position = vector(1, 2, 3),
    yaw = 5 * math.pi, pitch = -1, max_pitch = 0.5,
    mouse_sensitivity = 0.01, mouse_y_inverted = true,
    radius = 0.25, height = 1.75, eye_height = 1.4,
    mass = 80, friction = 0.2,
    speed = 4, speed_scale = 0.25, max_acceleration = 20, max_push_force = 100,
    max_floor_angle = 0.2,
    max_step_height = 0.3, step_search_distance = 0.1,
    ground_tolerance = 0.04, contact_tolerance = 0.005,
    tag = "hero",
    push_limit_filter = "movable",
    ground_filter = "floor",
    step_filter = "stairs",
    obstruction_filter = "solid",
  })

  luaunit.assert_equals({collider:getPosition()}, {1, 2, 3})
  luaunit.assert_equals(collider.radius, 0.25)
  luaunit.assert_equals(collider.length, 1.25)
  luaunit.assert_equals(collider.shape.offset_position, vector.zero)
  luaunit.assert_equals(
    collider.shape.offset_orientation,
    quaternion.angleaxis(math.pi / 2, 1, 0, 0)
  )
  luaunit.assert_equals(collider.tag, "hero")
  luaunit.assert_equals(collider.configured_mass, 80)
  luaunit.assert_equals(collider.friction, 0.2)
  luaunit.assert_equals(collider.restitution, 0)
  luaunit.assert_true(collider.continuous)
  luaunit.assert_false(collider.sleeping_allowed)
  luaunit.assert_equals(collider.degrees_of_freedom, {"xyz", ""})

  luaunit.assert_equals(world.new_capsule_collider_arguments[1], vector(1, 2, 3))
  luaunit.assert_equals(world.new_capsule_collider_arguments[2], 0.25)
  luaunit.assert_almost_equals(world.new_capsule_collider_arguments[3], 1.25)

  luaunit.assert_equals(controller.world, world)
  luaunit.assert_almost_equals(controller.yaw, math.pi, 1e-9)
  luaunit.assert_almost_equals(controller.pitch, -0.5, 1e-9)
  luaunit.assert_equals(controller.max_pitch, 0.5)
  luaunit.assert_equals(controller.mouse_sensitivity, 0.01)
  luaunit.assert_true(controller.mouse_y_inverted)
  luaunit.assert_equals(controller.radius, 0.25)
  luaunit.assert_equals(controller.height, 1.75)
  luaunit.assert_equals(controller.eye_height, 1.4)
  luaunit.assert_equals(controller.mass, 80)
  luaunit.assert_equals(controller.speed, 4)
  luaunit.assert_equals(controller.speed_scale, 0.25)
  luaunit.assert_equals(controller.max_acceleration, 20)
  luaunit.assert_equals(controller.max_push_force, 100)
  luaunit.assert_equals(controller.max_floor_angle, 0.2)
  luaunit.assert_equals(controller.max_step_height, 0.3)
  luaunit.assert_equals(controller.step_search_distance, 0.1)
  luaunit.assert_equals(controller.ground_tolerance, 0.04)
  luaunit.assert_equals(controller.contact_tolerance, 0.005)
  luaunit.assert_equals(controller.push_limit_filter, "movable")
  luaunit.assert_equals(controller.ground_filter, "floor")
  luaunit.assert_equals(controller.step_filter, "stairs")
  luaunit.assert_equals(controller.obstruction_filter, "solid")
  luaunit.assert_equals(controller.collider, collider)
  luaunit.assert_nil(controller.ground_collider)
  luaunit.assert_nil(controller.ground_shape)
end

-- TestFPController / Camera and direct controls

function TestFPController.test_get_camera_position()
  local world = MockWorld:new(MockCollider:new())
  local controller = FPController:new(world, {
    position = vector(4, 5, 6),
    height = 2, eye_height = 1.6,
  })
  local position = controller:get_camera_position()

  luaunit.assert_equals(position, vector(4, 5.6, 6))
end

function TestFPController.test_get_camera_orientation()
  local world = MockWorld:new(MockCollider:new())
  local controller = FPController:new(world, {
    yaw = math.pi / 2, pitch = math.pi / 6,
  })
  local orientation = controller:get_camera_orientation()

  local x, y, z = (orientation * vector.forward):unpack()

  luaunit.assert_almost_equals(x, math.cos(math.pi / 6), 1e-9)
  luaunit.assert_almost_equals(y, 0.5, 1e-9)
  luaunit.assert_almost_equals(z, 0, 1e-9)
end

function TestFPController.test_get_camera_direction()
  local world = MockWorld:new(MockCollider:new())
  local controller = FPController:new(world, {
    yaw = math.pi / 2, pitch = math.pi / 6,
  })
  local direction = controller:get_camera_direction()

  luaunit.assert_almost_equals(direction.x, math.cos(math.pi / 6), 1e-9)
  luaunit.assert_almost_equals(direction.y, 0.5, 1e-9)
  luaunit.assert_almost_equals(direction.z, 0, 1e-9)
end

function TestFPController.test_apply_mouse_move_wraps_yaw_and_clamps_pitch()
  local world = MockWorld:new(MockCollider:new())
  local controller = FPController:new(world, {
    max_pitch = 0.5,
    mouse_sensitivity = 1,
  })

  controller:apply_mouse_move(-math.pi / 2, -100)
  luaunit.assert_almost_equals(controller.yaw, 3 * math.pi / 2, 1e-9)
  luaunit.assert_equals(controller.pitch, 0.5)

  controller:apply_mouse_move(0, 200)
  luaunit.assert_equals(controller.pitch, -0.5)
end

function TestFPController.test_apply_mouse_move_can_invert_vertical_axis()
  local world = MockWorld:new(MockCollider:new())
  local controller = FPController:new(world, {
    mouse_sensitivity = 0.1, mouse_y_inverted = true,
  })

  controller:apply_mouse_move(2, 3)

  luaunit.assert_almost_equals(controller.yaw, 0.2, 1e-9)
  luaunit.assert_almost_equals(controller.pitch, 0.3, 1e-9)
end

function TestFPController.test_teleport()
  local collider = MockCollider:new()
  collider:setLinearVelocity(vector(1, 2, 3))

  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}

  local controller = FPController:new(world)

  -- populate `ground_collider` and `ground_shape` before teleporting
  local is_grounded = controller:is_grounded()
  luaunit.assert_true(is_grounded)

  controller:teleport(vector(4, 5, 6))

  luaunit.assert_equals({collider:getPosition()}, {4, 5, 6})
  luaunit.assert_equals({collider:getLinearVelocity()}, {0, 0, 0})
  luaunit.assert_nil(controller.ground_collider)
  luaunit.assert_nil(controller.ground_shape)
end

-- TestFPController / Ground detection

function TestFPController.test_is_grounded_queries_below_capsule_and_exposes_hit()
  local ground_collider, ground_shape = {}, {}
  local world = MockWorld:new(MockCollider:new())
  world.raycast_results = {_ground_hit({ collider = ground_collider, shape = ground_shape })}

  local controller = FPController:new(world, {
    position = vector(1, 2, 3),
    ground_tolerance = 0.1, contact_tolerance = 0.02,
    ground_filter = "walkable",
  })

  local is_grounded = controller:is_grounded()

  luaunit.assert_true(is_grounded)
  luaunit.assert_equals(
    world.raycast_calls[1],
    {vector(1, 1.12, 3), vector(1, 1, 3), "walkable"}
  )
  luaunit.assert_equals(controller.ground_collider, ground_collider)
  luaunit.assert_equals(controller.ground_shape, ground_shape)
end

function TestFPController.test_is_grounded_rejects_invalid_hits_and_clears_previous_hit()
  local world = MockWorld:new(MockCollider:new())
  world.raycast_results = {
    _ground_hit({ normal = vector(0, math.cos(math.rad(9)), 0) }),
    _ground_hit({ normal = vector(0, math.cos(math.rad(11)), 0) }),
    {true, true, 0, 0, 0, 0},
    false,
  }

  local controller = FPController:new(world, { max_floor_angle = math.rad(10) })

  -- raycast result #1
  luaunit.assert_true(controller:is_grounded())

  -- raycast result #2
  luaunit.assert_false(controller:is_grounded())
  luaunit.assert_nil(controller.ground_collider)
  luaunit.assert_nil(controller.ground_shape)

  -- raycast result #3
  luaunit.assert_false(controller:is_grounded())

  -- raycast result #4
  luaunit.assert_false(controller:is_grounded())
end

-- TestFPController / Walking

function TestFPController.test_walking_rotates_local_input_by_yaw()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}

  local controller = FPController:new(world, {
    yaw = math.pi / 2,
    mass = 10,
    speed = 4, max_acceleration = 100,
  })

  controller:pre_physics_update(1, 0, -1)

  luaunit.assert_almost_equals(collider.force.x, 40, 1e-9)
  luaunit.assert_almost_equals(collider.force.y, 0, 1e-9)
  luaunit.assert_almost_equals(collider.force.z, 0, 1e-9)
end

function TestFPController.test_walking_preserves_analog_magnitude_and_clamps_diagonal_input()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  local controller = FPController:new(world, {
    mass = 10,
    speed = 4, max_acceleration = 100,
    max_step_height = 0,
  })
  world.raycast_results = {_ground_hit(), _ground_hit()}

  controller:pre_physics_update(1, 0.5, 0)
  luaunit.assert_equals(collider.force, vector(20, 0, 0))

  collider:setLinearVelocity(vector.zero)
  controller:pre_physics_update(1, 1, -1)
  luaunit.assert_almost_equals(collider.force.x, 40 / math.sqrt(2), 1e-9)
  luaunit.assert_almost_equals(collider.force.z, -40 / math.sqrt(2), 1e-9)
end

function TestFPController.test_walking_limits_acceleration_and_brakes_without_input()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit(), _ground_hit()}

  local controller = FPController:new(world, {
    mass = 10,
    speed = 10, max_acceleration = 3,
    max_step_height = 0,
  })

  controller:pre_physics_update(0.1, 0, -1)
  luaunit.assert_almost_equals(collider.force.z, -30, 1e-9)

  collider:setLinearVelocity(vector(4, 0, -3))
  controller:pre_physics_update(1, 0, 0)
  luaunit.assert_almost_equals(collider.force.x, -24, 1e-9)
  luaunit.assert_almost_equals(collider.force.z, 18, 1e-9)
  luaunit.assert_equals(#world.shapecast_calls, 1)
end

function TestFPController.test_airborne_controller_preserves_horizontal_momentum()
  local collider = MockCollider:new()
  collider:setLinearVelocity(vector(1, -2, 3))

  local world = MockWorld:new(collider)
  world.raycast_results = {false, false}

  local controller = FPController:new(world)

  controller:pre_physics_update(0.1, 1, -1)

  luaunit.assert_equals({collider:getLinearVelocity()}, {1, -2, 3})
  luaunit.assert_equals(#collider.applied_forces, 0)
  luaunit.assert_equals(#world.raycast_calls, 2)
  luaunit.assert_equals(#world.shapecast_calls, 0)
end

function TestFPController.test_near_ground_controller_can_move_but_does_not_step_up()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {false, _ground_hit()}

  local controller = FPController:new(world, { max_acceleration = 100 })

  controller:pre_physics_update(0.1, 0, -1)

  luaunit.assert_true(collider.force.z < 0)
  luaunit.assert_equals(#world.raycast_calls, 2)
  luaunit.assert_equals(world.raycast_calls[1][2].y, -0.98)
  luaunit.assert_almost_equals(world.raycast_calls[2][2].y, -1.16, 1e-9)
end

function TestFPController.test_speed_scale_changes_desired_walking_speed()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}

  local controller = FPController:new(world, {
    mass = 10,
    speed = 4, speed_scale = 0.5, max_acceleration = 100,
  })

  controller:pre_physics_update(1, 0, -1)

  luaunit.assert_almost_equals(collider.force.z, -20, 1e-9)
end

-- TestFPController / Dynamic-body push limiting

function TestFPController.test_walking_shapecasts_predicted_displacement_for_dynamic_bodies()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}

  local controller = FPController:new(world, {
    position = vector(1, 2, 3),
    mass = 10,
    speed = 4, max_acceleration = 100,
    max_step_height = 0,
    contact_tolerance = 0.1,
    push_limit_filter = "pushable",
  })

  controller:pre_physics_update(0.5, 0, -1)

  luaunit.assert_equals(#world.shapecast_calls, 1)

  local arguments = world.shapecast_calls[1]
  luaunit.assert_equals(arguments[1], collider.shape)
  luaunit.assert_equals(arguments[2], vector(1, 2, 3))
  luaunit.assert_almost_equals(arguments[3].x, 1, 1e-9)
  luaunit.assert_equals(arguments[3].y, 2)
  luaunit.assert_almost_equals(arguments[3].z, 0.9, 1e-9)
  luaunit.assert_equals(arguments[4], quaternion.angleaxis(math.pi / 2, 1, 0, 0))
  luaunit.assert_equals(arguments[5], "pushable")
end

function TestFPController.test_walking_limits_normal_push_force_and_preserves_tangent_force()
  local collider, dynamic_collider = MockCollider:new(), MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}
  world.shapecast_results = {
    _dynamic_hit(dynamic_collider, {
      position = vector(1, 2, 3),
      normal = vector.backward,
    }),
  }

  local controller = FPController:new(world, {
    mass = 10,
    speed = 4, max_acceleration = 100,
    max_push_force = 25,
    max_step_height = 0,
  })

  controller:pre_physics_update(0.5, 1, -1)

  luaunit.assert_almost_equals(collider.force.x, 80 / math.sqrt(2), 1e-9)
  luaunit.assert_almost_equals(collider.force.z, -25, 1e-9)
  luaunit.assert_equals(dynamic_collider.velocity_point, vector(1, 2, 3))
end

function TestFPController.test_walking_does_not_limit_push_when_body_moves_away()
  local collider, dynamic_collider = MockCollider:new(), MockCollider:new()
  dynamic_collider.surface_velocity = vector(0, 0, -5)

  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}
  world.shapecast_results = {_dynamic_hit(dynamic_collider)}

  local controller = FPController:new(world, {
    mass = 10,
    speed = 4, max_acceleration = 100,
    max_push_force = 25,
    max_step_height = 0,
  })

  controller:pre_physics_update(0.5, 0, -1)

  luaunit.assert_almost_equals(collider.force.z, -80, 1e-9)
end

function TestFPController.test_walking_ignores_hit_without_horizontal_normal()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit()}
  world.shapecast_results = {
    _dynamic_hit(MockCollider:new(), { normal = vector.up }),
  }

  local controller = FPController:new(world, {
    mass = 10,
    speed = 4, max_acceleration = 100,
    max_push_force = 25,
    max_step_height = 0,
  })

  controller:pre_physics_update(0.5, 0, -1)

  luaunit.assert_almost_equals(collider.force.z, -80, 1e-9)
end

-- TestFPController / Automatic step-up

function TestFPController.test_walking_steps_onto_clear_walkable_surface()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit(), _ground_hit({ position = vector(0, 0.2, 0) })}

  local controller = FPController:new(world, {
    position = vector(0, 0.9, 0),
    max_acceleration = 100,
  })

  controller:pre_physics_update(0.1, 0, -1)

  luaunit.assert_almost_equals(collider.position.y, 1.11, 1e-9)
  luaunit.assert_equals(#world.overlap_calls, 1)
  luaunit.assert_equals(world.overlap_calls[1][1], collider.shape)
  luaunit.assert_almost_equals(world.overlap_calls[1][2].y, 1.11, 1e-9)
  luaunit.assert_equals(world.overlap_calls[1][5], controller.obstruction_filter)
end

function TestFPController.test_step_search_uses_direction_distance_and_step_filter()
  local world = MockWorld:new(MockCollider:new())
  world.raycast_results = {_ground_hit(), false}

  local controller = FPController:new(world, {
    position = vector(1, 2, 3),
    radius = 0.3,
    max_acceleration = 100,
    max_step_height = 0.25, step_search_distance = 0.2,
    ground_tolerance = 0.08, contact_tolerance = 0.01,
    step_filter = "stairs",
  })

  controller:pre_physics_update(0.1, 1, 0)

  luaunit.assert_equals(world.raycast_calls[2], {
    vector(1.5, 1.36, 3),
    vector(1.5, 1.02, 3),
    "stairs",
  })
end

function TestFPController.test_walking_does_not_step_onto_invalid_surface()
  for _, case in ipairs({
    { name = "missing", hit = false },
    { name = "steep", hit = _ground_hit({
      position = vector(0, 0.2, 0),
      normal = vector.zero,
    }) },
    { name = "too low", hit = _ground_hit({ position = vector(0, 0.005, 0) }) },
    { name = "too high", hit = _ground_hit({ position = vector(0, 0.3, 0) }) },
  }) do
    local collider = MockCollider:new()
    local world = MockWorld:new(collider)
    world.raycast_results = {_ground_hit(), case.hit}

    local controller = FPController:new(world, {
      position = vector(0, 0.9, 0),
      max_acceleration = 100,
    })

    controller:pre_physics_update(0.1, 0, -1)

    luaunit.assert_equals(collider.position.y, 0.9, case.name)
    luaunit.assert_equals(#world.overlap_calls, 0, case.name)
  end
end

function TestFPController.test_walking_does_not_step_into_obstruction()
  local collider = MockCollider:new()
  local world = MockWorld:new(collider)
  world.raycast_results = {_ground_hit(), _ground_hit({ position = vector(0, 0.2, 0) })}
  world.overlap_results = {{}}

  local controller = FPController:new(world, {
    position = vector(0, 0.9, 0),
    max_acceleration = 100,
  })

  controller:pre_physics_update(0.1, 0, -1)

  luaunit.assert_equals(collider.position.y, 0.9)
end

function TestFPController.test_zero_maximum_step_height_disables_step_search()
  local world = MockWorld:new(MockCollider:new())
  world.raycast_results = {_ground_hit()}

  local controller = FPController:new(world, {
    max_acceleration = 100,
    max_step_height = 0,
  })

  controller:pre_physics_update(0.1, 0, -1)

  luaunit.assert_equals(#world.raycast_calls, 1)
  luaunit.assert_equals(#world.overlap_calls, 0)
end
