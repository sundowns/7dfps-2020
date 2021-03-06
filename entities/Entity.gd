extends KinematicBody
class_name Entity

export(float) var gravity: float = 10
export(float) var falling_gravity_modifier: float = 1.0
export(float) var max_health: float = 100
export(float) var mass: float = 100
export(float) var knockback_drag: float = 5.0

const terminal_fall_velocity: float = -40.0
const base_mass: float = 100.0

onready var ground_check: GroundCheck = $GroundCheck
onready var health = max_health

var gravity_vector := Vector3.ZERO
var velocity := Vector3.ZERO
var knockback := Vector3.ZERO
var is_dead := false

const maximum_walkable_slope_angle: float = 50.0

signal heal(new_health)
signal hurt(new_health)
signal dead

func _physics_process(delta):
	apply_knockback_force(delta)

func apply_gravity(delta: float, slope_angle: float = 0.0, force_push_into_floor_normal: bool = false):
	if not is_on_floor() and not ground_check.is_grounded():
		var gravity_force = Vector3.DOWN * gravity * delta
		if gravity_vector.y < 0:
			gravity_force *= falling_gravity_modifier
		gravity_vector += gravity_force
		gravity_vector.y = max(gravity_vector.y, terminal_fall_velocity)
	# Just ignoring ground-based gravity vector if the entity has JUST been pushed (so it can leave the ground)
	else:
		if force_push_into_floor_normal:
			gravity_vector = -get_floor_normal()
		else:
			if is_on_floor() and ground_check.is_grounded():
				if slope_angle >= maximum_walkable_slope_angle:
					gravity_vector = Vector3.DOWN * gravity
				else:
					gravity_vector = -get_floor_normal() * gravity
			else:
				if slope_angle >= maximum_walkable_slope_angle:
					gravity_vector = Vector3.DOWN * gravity
				else:
					gravity_vector = -get_floor_normal()

func apply_knockback_force(delta):
	if knockback.length() <= 0:
		return
# warning-ignore:return_value_discarded
	move_and_slide(knockback, Vector3.UP)
	# Reduce the knockback...
	knockback = knockback.move_toward(Vector3.ZERO, delta * knockback_drag)

func handle_ceiling_bonk():
	if is_on_ceiling() and gravity_vector.y > 0:
		gravity_vector.y = 0

func update_health(delta: float):
	if is_dead:
		return
	health += delta
	health = clamp(health, 0, max_health)
	if delta < 0:
		emit_signal("hurt", health)
	if delta > 0:
		emit_signal("heal", health)
	if health <= 0:
		emit_signal("dead")

func push(raw_knockback_force: Vector3):
	knockback += raw_knockback_force * (mass/base_mass)
