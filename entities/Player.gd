extends Entity
class_name Player

onready var head: Spatial = $Head
onready var camera: Camera = $Head/Camera
onready var hand: Spatial = $Head/Hand
onready var hand_location: Spatial = $Head/HandLocation
onready var aim_cast: RayCast = $Head/Camera/AimCast
onready var interact_cast: RayCast = $Head/Camera/InteractCast
onready var state_machine: StateMachine = $MovementStateMachine
onready var landing_audio: AudioStreamPlayer3D = $LandingAudio

# Player movement values
export var ground_speed: float = 10
export var ground_acceleration: float = 16
export var ground_friction: float = 4
export var jump_force: float = 5 # Initial vertical impulse when jumping

export var aerial_speed: float = 12
export var aerial_acceleration: float = 4 # 4.5 juicy but quite high
export var aerial_drag: float = 6

const strafe_viewport_rotation_speed := deg2rad(25)
const max_strafe_viewport_rotation := deg2rad(0.75)
const weapon_sway := 35

var strafe_viewport_rotation = 0
var direction = Vector3.ZERO
var just_jumped := false
var just_fell := true
var active_weapon: Gun = null
var sensitivity_multipler: float = 1
var is_switching_weapons := false
var next_weapon_index := 1
var rng = RandomNumberGenerator.new()

onready var weapon_list = {
	1: $Head/Hand/Revolver,
	2: $Head/Hand/Shotgun
}

signal ammo_changed(new_ammo)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(deg2rad(-event.relative.x * Global.mouse_sensitivity))
		head.rotate_x(deg2rad(-event.relative.y * Global.mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg2rad(-89), deg2rad(89))

func initialise():
	Global.player_node = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	active_weapon = weapon_list.get(1)
	call_deferred("connect_ui")
	for weapon in weapon_list.values():
		weapon.initialise()
	call_deferred("switch_to_next_weapon")
# warning-ignore:return_value_discarded
	connect("hurt", self, "_on_player_hurt")
	rng.randomize()

func connect_ui():
	var ui_node = get_tree().current_scene.find_node("HUD", true, false)
# warning-ignore:return_value_discarded
	state_machine.connect("state_changed", ui_node, "_on_player_state_updated")
# warning-ignore:return_value_discarded
	connect("ammo_changed", ui_node, "_on_player_ammo_updated")
# warning-ignore:return_value_discarded
	connect("hurt", ui_node, "_on_player_health_updated")
	call_deferred("_on_gun_reload", active_weapon.current_ammo)
	
func _process(delta):
	handle_viewport_lean(delta)
	handle_weapon_sway(delta)

func _physics_process(_delta):
	handle_weapon_switch()
	handle_shooting()
	handle_interaction()

func apply_movement():
	var movement = Vector3.ZERO
	movement.z = velocity.z + gravity_vector.z
	movement.x = velocity.x + gravity_vector.x
	movement.y = gravity_vector.y
# warning-ignore:return_value_discarded
	move_and_slide(movement, Vector3.UP)

func grounded_movement(delta: float):
	direction = Vector3.ZERO

	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	elif Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	elif Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	direction = direction.normalized()
	velocity = velocity.linear_interpolate(direction * ground_speed, ground_acceleration * delta)
	velocity = velocity.move_toward(Vector3(0, velocity.y, 0), delta * ground_friction)
	if velocity.length() > 5:
		if !$FootstepAudio.is_playing():
			$FootstepAudio.play()

func aerial_movement(delta):
	direction = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	elif Input.is_action_pressed("move_backward"):
		direction += transform.basis.z
	
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	elif Input.is_action_pressed("move_right"):
		direction += transform.basis.x
		
	direction = direction.normalized()
	if direction != Vector3.ZERO:
		velocity = velocity.linear_interpolate(direction * aerial_speed, aerial_acceleration * delta)
	velocity = velocity.move_toward(Vector3(0, velocity.y, 0), delta * aerial_drag)
	.handle_ceiling_bonk()

func handle_weapon_sway(delta):
	hand.global_transform.origin = hand_location.global_transform.origin
	hand.rotation.y = lerp_angle(hand.rotation.y, rotation.y, weapon_sway * delta)
	hand.rotation.x = lerp_angle(hand.rotation.x, head.rotation.x, weapon_sway * delta)
	hand.rotation.z = 0 # I don't know why this gets set to -180 on startup sometimes..but whatever

func handle_jump():
	if Input.is_action_pressed("jump"):
		if is_on_floor() or ground_check.is_grounded():
			$JumpAudio.play()
			jump()

func handle_shooting():
	if not active_weapon or active_weapon.is_reloading or is_switching_weapons:
		return
	if Input.is_action_just_pressed("reload"):
		active_weapon.start_reload()
	
	if Input.is_action_just_pressed("fire") or (Input.is_action_pressed("fire")):
		if aim_cast.is_colliding() and active_weapon.is_ready:
			active_weapon.shoot(aim_cast, head.global_transform.origin)
			emit_signal("ammo_changed", active_weapon.current_ammo)

func handle_interaction():
	if not interact_cast.is_colliding():
		return
	if Input.is_action_just_pressed("use"):
		var collider = interact_cast.get_collider()
		if collider is InteractableHitbox:
			collider.interact()

func jump(height_modifier: float = 1.0):
	gravity_vector = Vector3.UP * jump_force * height_modifier
	state_machine.exit_and_change_to("Jump")

func handle_viewport_lean(delta):
	if Input.is_action_pressed("move_left"):
		strafe_viewport_rotation += strafe_viewport_rotation_speed * delta
	elif Input.is_action_pressed("move_right"):
		strafe_viewport_rotation -= strafe_viewport_rotation_speed * delta
	elif strafe_viewport_rotation != 0:
		strafe_viewport_rotation = strafe_viewport_rotation * 0.975 * delta

	strafe_viewport_rotation = clamp(strafe_viewport_rotation, -max_strafe_viewport_rotation, max_strafe_viewport_rotation)
	camera.rotation.z = strafe_viewport_rotation

func handle_weapon_switch():
	if active_weapon and active_weapon.is_reloading:
		return
	for i in range(1,3):
		if Input.is_action_just_pressed("weapon_%d" % i):
			begin_weapon_switch(i)

func begin_weapon_switch(weapon_index: int):
	assert(weapon_list.has(weapon_index), "No weapon at weapon index %d" % weapon_index)
	if weapon_list[weapon_index] == active_weapon:
		return
	is_switching_weapons = true
	next_weapon_index = weapon_index
	if active_weapon:
		active_weapon.holster()

func switch_to_next_weapon():
	assert(next_weapon_index != -1, "Switching to weapon called without next_weapon_index set")
	if weapon_list.size() == 0:
		return
	active_weapon = weapon_list[next_weapon_index]
	for weapon in weapon_list.values():
		weapon.hide()
	active_weapon.show()
	active_weapon.unholster()
	emit_signal("ammo_changed", active_weapon.current_ammo)


func _on_gun_holstered():
	if weapon_list.has(next_weapon_index):
		switch_to_next_weapon()

func _on_gun_unholstered():
	is_switching_weapons = false

func _exit_tree():
	Global.player_node = null

func hit_by_bandit(damage: float, knockback: Vector3):
	update_health(-damage)
	push(knockback)

func _on_gun_reload(new_ammo_count):
	emit_signal("ammo_changed", new_ammo_count)
	
func _on_player_hurt(_val):
	var n = rng.randi_range(0, $HurtAudio.get_child_count() -1)
	$HurtAudio.get_child(n).play()
		
