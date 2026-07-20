class_name Player
extends CharacterBody3D

signal weapon_switched(weapon_name: String)

enum WEAPON_TYPE { DEFAULT, GRENADE }

## Character maximum run speed on the ground.
@export var move_speed := 8.0
## Forward impulse after a melee attack.
@export var attack_impulse := 10.0
## Movement acceleration (how fast character achieve maximum speed)
@export var acceleration := 4.0
## Jump impulse
@export var jump_initial_impulse := 12.0
## Jump impulse when player keeps pressing jump
@export var jump_additional_force := 5.0
## Player model rotation speed
@export var rotation_speed := 12.0
## Minimum horizontal speed on the ground. This controls when the character's animation tree changes
## between the idle and running states.
@export var stopping_speed := 1.0
## Max throwback force after player takes a hit
@export var max_throwback_force := 15.0
## Force to bounce off when landing on another player's head or on top of an enemy
@export var bounce_off_force: Vector3 = Vector3(20.0, 10.0, 20.0)
## Add an offset to the spawn location of the coins the player loses
@export var lost_coins_upward_offset: float = 1.0
## Projectile cooldown
@export var shoot_cooldown := 0.5
## Grenade cooldown
@export var grenade_cooldown := 0.5
## If melee attacks can damage other players
@export var friendly_fire: bool = false

@onready var _bullet_spawner: BulletSpawner = $BulletSpawner
@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _camera: Camera3D = $CameraController/PlayerCamera
@onready var _attack_animation_player: AnimationPlayer = $CharacterRotationRoot/MeleeAnchor/AnimationPlayer
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var _grenade_aim_controller: GrenadeLauncher = $GrenadeLauncher
@onready var _melee_attack_area: MeleeAttackArea = $CharacterRotationRoot/MeleeAttackArea
@onready var _character_skin: CharacterSkin = $CharacterRotationRoot/CharacterSkin
@onready var _username: Label3D = $Username
@onready var _ui_HUD: Control = %HUD
@onready var _ui_aim_reticle: ColorRect = %AimReticle
@onready var _ui_coins_container: HBoxContainer = %CoinsContainer
@onready var _ui_weapon: WeaponUI = %WeaponUI
@onready var _step_sound: AudioStreamPlayer3D = $StepSound
@onready var _landing_sound: AudioStreamPlayer3D = $LandingSound

@onready var _start_position: Vector3 = global_transform.origin
@onready var _shoot_cooldown_tick := shoot_cooldown
@onready var _grenade_cooldown_tick := grenade_cooldown

var _equipped_weapon: WEAPON_TYPE = WEAPON_TYPE.DEFAULT
var _move_direction: Vector3 = Vector3.ZERO
var _last_strong_direction: Vector3 = Vector3.FORWARD
var _gravity: float = -30.0
var _ground_height: float = 0.0
var _coins: int = 0
var _is_on_floor_buffer: bool = false

var peer_id: int = 1 # The peer that controls this player
var local: bool = true # If this instance is controlled by the local peer

var display_name: String = "":
	set(value):
		display_name = value
		if _username != null and not value.is_empty():
			_username.text = value

var custom_color: Color = Color.TRANSPARENT:
	set(value):
		custom_color = value
		if _character_skin != null and is_equal_approx(value.a, 1.0):
			_character_skin.set_color(value)

# Cache inputs and movement state
var raw_move_input: Vector2 = Vector2.ZERO
var is_attack_held: bool = false
var is_just_attacking: bool = false
var is_jump_held: bool = false
var is_just_jumping: bool = false
var is_aim_held: bool = false
var is_swapping_weapons: bool = false

var is_using_jumping_pad: bool = false
var is_bouncing: bool = false

func _enter_tree() -> void:
	# Set node authority
	peer_id = int(name)
	local = (peer_id == multiplayer.get_unique_id())
	set_physics_process(local)

func _exit_tree() -> void:
	if local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	if local and !get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)

	if _ui_HUD != null:
		_ui_HUD.visible = local
	if local and _ui_weapon != null:
		weapon_switched.connect(_ui_weapon.switch_to)
	_grenade_aim_controller.visible = false
	weapon_switched.emit(WEAPON_TYPE.keys()[0])

	_melee_attack_area.attacker = self
	_melee_attack_area.friendly_fire = friendly_fire

	# When copying this character to a new project, the project may lack required input actions.
	# In that case, we register input actions for the user at runtime.
	if not InputMap.has_action("move_left"):
		_register_input_actions()

	_character_skin.stepped.connect(play_foot_step_sound)

	set_multiplayer_data.call_deferred()

func generate_random_hsv_color(color_seed: int) -> Color:
	var rng = RandomNumberGenerator.new()
	rng.seed = color_seed
	return Color.from_hsv(
		rng.randf(), # HUE
		rng.randf_range(0.2, 0.6), # SATURATION
		rng.randf_range(0.9, 1.0), # BRIGHTNESS
 	)

func set_multiplayer_data():
	# Give authority to this client
	const recursive: bool = false
	set_multiplayer_authority(peer_id, recursive)
	if !recursive:
		$ClientSynchronizer.set_multiplayer_authority(peer_id, false)
		_bullet_spawner.set_multiplayer_authority(peer_id, false)
		_grenade_aim_controller._grenade_spawner.set_multiplayer_authority(peer_id, false)
	
	if local:
		var lobby: Lobby = get_node("/root/Lobby")
		if lobby != null:
			display_name = lobby.local_player_name
			custom_color = lobby.local_player_color
	
	# Give the player model the color of this client
	var player_color: Color = custom_color if (is_equal_approx(custom_color.a, 1.0)) else generate_random_hsv_color(peer_id)
	_character_skin.set_color(player_color)
	
	# Display the username of this client
	var player_name: String = display_name if (not display_name.is_empty()) else "Player " + name
	_username.text = player_name
	
	# Make sure to only display the username of OTHER players, not yourself
	_username.visible = !local
	
	if (local):
		# Activate the camera if local
		_camera.make_current()

func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action("move_left")
		or event.is_action("move_right")
		or event.is_action("move_up")
		or event.is_action("move_down")):
			raw_move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	elif event.is_action("jump"):
		is_just_jumping = event.is_action_pressed("jump")
		is_jump_held = event.is_action_pressed("jump", true)
	elif event.is_action("attack"):
		is_attack_held = event.is_action_pressed("attack", true)
		is_just_attacking = event.is_action_pressed("attack")
	elif event.is_action("aim"):
		is_aim_held = event.is_action_pressed("aim", true)
	elif event.is_action("swap_weapons"):
		is_swapping_weapons = event.is_action_pressed("swap_weapons")

func _physics_process(delta: float) -> void:
	# Only process physics if local
	if (!local): return
	
	# Calculate ground height for camera controller
	if _ground_shapecast.get_collision_count() > 0:
		for collision_result in _ground_shapecast.collision_result:
			_ground_height = max(_ground_height, collision_result.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y

	# Swap weapons
	if is_swapping_weapons:
		_equipped_weapon = WEAPON_TYPE.DEFAULT if _equipped_weapon == WEAPON_TYPE.GRENADE else WEAPON_TYPE.GRENADE
		_grenade_aim_controller.visible = _equipped_weapon == WEAPON_TYPE.GRENADE
		weapon_switched.emit(WEAPON_TYPE.keys()[_equipped_weapon])

	# Get movement state from input
	var is_attacking: bool = is_attack_held and not _attack_animation_player.is_playing()
	is_just_jumping = is_just_jumping and is_on_floor()
	var is_aiming = is_aim_held and is_on_floor()
	var is_air_boosting = is_jump_held and not is_on_floor() and velocity.y > 0.0
	var is_just_on_floor: bool = is_on_floor() and not _is_on_floor_buffer
	is_using_jumping_pad = is_using_jumping_pad and velocity.y > 0.0

	_is_on_floor_buffer = is_on_floor()
	_move_direction = _get_camera_oriented_input()

	# To not orient quickly to the last input, we save a last strong direction,
	# this also ensures a good normalized value for the rotation basis.
	if _move_direction.length() > 0.2:
		_last_strong_direction = _move_direction.normalized()
	if is_aiming:
		_last_strong_direction = (_camera_controller.global_transform.basis * Vector3.BACK).normalized()

	_orient_character_to_direction(_last_strong_direction, delta)

	# We separate out the y velocity to not interpolate on the gravity
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.lerp(_move_direction * move_speed, acceleration * delta)
	if _move_direction.length() == 0 and velocity.length() < stopping_speed:
		velocity = Vector3.ZERO
	velocity.y = y_velocity

	# Set aiming camera and UI
	if is_aiming:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.OVER_SHOULDER)
		_grenade_aim_controller.throw_direction = _camera_controller.camera.quaternion * Vector3.FORWARD
		_grenade_aim_controller.from_look_position = _camera_controller.camera.global_position
		_ui_aim_reticle.visible = true
	else:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.THIRD_PERSON)
		_grenade_aim_controller.throw_direction = _last_strong_direction
		_grenade_aim_controller.from_look_position = global_position
		_ui_aim_reticle.visible = false

	# Update attack state and position

	_shoot_cooldown_tick += delta
	_grenade_cooldown_tick += delta

	if is_attacking:
		match _equipped_weapon:
			WEAPON_TYPE.DEFAULT:
				if is_aiming and is_on_floor():
					if _shoot_cooldown_tick > shoot_cooldown:
						_shoot_cooldown_tick = 0.0
						shoot()
				elif is_just_attacking:
					attack.rpc()
			WEAPON_TYPE.GRENADE:
				if _grenade_cooldown_tick > grenade_cooldown:
					_grenade_cooldown_tick = 0.0
					_grenade_aim_controller.throw_grenade()

	velocity.y += _gravity * delta

	if not is_using_jumping_pad and not is_bouncing:
		if is_just_jumping:
			velocity.y += jump_initial_impulse
		elif is_air_boosting:
			velocity.y += jump_additional_force * delta

	# Set character animation
	if is_just_jumping:
		_character_skin.jump()
	elif not is_on_floor() and velocity.y < 0:
		_character_skin.fall()
	elif is_on_floor():
		var xz_velocity := Vector3(velocity.x, 0, velocity.z)
		if xz_velocity.length() > stopping_speed:
			_character_skin.set_moving(true)
			_character_skin.set_moving_speed.rpc(inverse_lerp(0.0, move_speed, xz_velocity.length()))
		else:
			_character_skin.set_moving(false)

	if is_just_on_floor:
		_landing_sound.play()

	var position_before := global_position
	move_and_slide()

	# Any "flat" surface can be considered as floor, but in some cases
	# we might want to exclude them (e.g. when landing on another
	# player's head or an enemy) and do some custom behaviour
	# like bounce away and/or take damage
	is_bouncing = false
	if is_on_floor():
		var collision: KinematicCollision3D = get_last_slide_collision()
		if (collision != null and
			collision.get_normal().dot(up_direction) >= 0.5):
			var collider: Object = collision.get_collider()
			var bounce_direction: Vector3 = Vector3.ZERO
			if collider.is_in_group("players"):
				# Bounce forward
				bounce_direction = (_last_strong_direction + up_direction).normalized()
			elif collider.is_in_group("enemies"):
				# Bounce away
				bounce_direction = (up_direction - _last_strong_direction).normalized()

			if bounce_direction != Vector3.ZERO:
				is_bouncing = true
				velocity = bounce_direction * bounce_off_force
				print_verbose("Bouncing player ", name, " off with velocity ", velocity)
				move_and_slide()

	var position_after := global_position

	# If velocity is not 0 but the difference of positions after move_and_slide is,
	# character might be stuck somewhere!
	var delta_position := position_after - position_before
	var epsilon := 0.001
	if delta_position.length() < epsilon and velocity.length() > epsilon:
		global_position += get_wall_normal() * 0.1

	# Reset inputs that shouldn't be processed multiple times
	is_just_attacking = false
	is_just_jumping = false
	is_swapping_weapons = false


@rpc("authority", "call_local", "reliable")
func attack() -> void:
	_attack_animation_player.play("Attack")
	_character_skin.punch()
	velocity = _rotation_root.transform.basis * Vector3.BACK * attack_impulse


func shoot() -> void:
	if not local:
		return
	var origin := global_position + Vector3.UP
	var aim_target := _camera_controller.get_aim_target()
	var _bullet: Bullet = _bullet_spawner.shoot(origin, aim_target)


@rpc("authority", "call_local", "reliable")
func teleport(new_pos: Vector3, new_rot: Vector3, reset_vel: bool = true) -> void:
	if reset_vel:
		velocity = Vector3.ZERO
	global_position = new_pos
	global_rotation = new_rot


func reset_position() -> void:
	transform.origin = _start_position


func collect_coins(count: int = 1) -> void:
	if not local:
		return
	
	_coins += count
	_ui_coins_container.update_coins_amount(_coins)


func lose_coins(count: int = 5, spawn_coins: bool = true) -> void:
	if not local:
		return
	
	var lost_coins: int = min(_coins, count)
	if lost_coins < 1:
		return
	
	_coins -= lost_coins
	_ui_coins_container.update_coins_amount(_coins)
	
	if spawn_coins:
		var spawn_position: Vector3 = global_position + up_direction * lost_coins_upward_offset
		_server_lost_coins.rpc_id(1, lost_coins, spawn_position)


@rpc("authority", "call_local", "reliable")
func _server_lost_coins(count: int, spawn_position: Vector3) -> void:
	Level.spawn_coins(spawn_position, count, 1.5)


func _get_camera_oriented_input() -> Vector3:
	if _attack_animation_player.is_playing():
		return Vector3.ZERO

	var input := Vector3.ZERO
	# This is to ensure that diagonal input isn't stronger than axis aligned input
	input.x = -raw_move_input.x * sqrt(1.0 - raw_move_input.y * raw_move_input.y / 2.0)
	input.z = -raw_move_input.y * sqrt(1.0 - raw_move_input.x * raw_move_input.x / 2.0)

	input = _camera_controller.global_transform.basis * input
	input.y = 0.0
	return input


func play_foot_step_sound() -> void:
	_step_sound.pitch_scale = randfn(1.2, 0.2)
	_step_sound.play()


func damage(_impact_point: Vector3, force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	# Always throws character up
	force.y = abs(force.y)
	velocity = force.limit_length(max_throwback_force)
	lose_coins()


func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	var left_axis := Vector3.UP.cross(direction)
	var rotation_basis := Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var model_scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(_rotation_root.transform.basis.get_rotation_quaternion().slerp(rotation_basis, delta * rotation_speed)).scaled(
		model_scale,
	)


## Used to register required input actions when copying this character to a different project.
func _register_input_actions() -> void:
	const INPUT_ACTIONS := {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_W,
		"move_down": KEY_S,
		"jump": KEY_SPACE,
		"attack": MOUSE_BUTTON_LEFT,
		"aim": MOUSE_BUTTON_RIGHT,
		"swap_weapons": KEY_TAB,
		"pause": KEY_ESCAPE,
		"camera_left": KEY_Q,
		"camera_right": KEY_E,
		"camera_up": KEY_R,
		"camera_down": KEY_F,
	}
	for action in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var input_key = InputEventKey.new()
		input_key.keycode = INPUT_ACTIONS[action]
		InputMap.action_add_event(action, input_key)
