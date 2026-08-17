class_name Player
extends CharacterBody3D

signal weapon_switched(weapon_name: String)

enum WEAPON_TYPE { DEFAULT, GRENADE }

@export_group("Movement")
## Character maximum run speed on the ground.
@export var move_speed := 8.0
## Forward impulse after a melee attack.
@export var attack_impulse := 10.0
## Movement acceleration (how fast character achieve maximum speed)
@export var acceleration := 6.0
## Jump impulse
@export var jump_initial_impulse := 12.0
## Jump impulse when player keeps pressing jump
@export var jump_additional_force := 5.0
## Player model rotation speed
@export var rotation_speed := 12.0
## Minimum horizontal speed on the ground. This controls when the character's animation tree changes
## between the idle and running states.
@export var stopping_speed := 1.0

@export_group("Taking Hits")
## Max throwback force after player takes a hit from any source (e.g. melee, bullet, grenade)
@export var max_throwback_force := 50.0
## Force to bounce off when landing on another player's head or on top of an enemy
@export var bounce_off_force: Vector3 = Vector3(20.0, 10.0, 20.0)
## Add an offset to the spawn location of the coins the player loses
@export var lost_coins_upward_offset: float = 1.0

@export_group("Projectiles")
## Bullets cooldown
@export var shoot_cooldown := 0.5
## Speed of shot bullets.
@export var bullet_speed: float = 14.0
## Distance limit after which shot bullets despawn.
@export var distance_limit: float = 14.0
## Grenade cooldown[br]
## [b]Note:[/b] For more grenade settings, see [GrenadeLauncher]
@export var grenade_cooldown := 0.5
## Aims in the camera direction, otherwise it aims in the direction the character is facing.
@export var aim_in_camera_direction: bool = false
## If the player can aim and shoot midair, otherwise jumping or falling cancels out the aim.
@export var can_shoot_midair: bool = true

@export_group("")
## If [code]true[/code], melee attacks and bullets can damage other players.[br]
## [b]Note:[/b] For grenades, see [GrenadeLauncher]
@export var friendly_fire: bool = false

@onready var _client_synchronizer: MultiplayerSynchronizer = $ClientSynchronizer
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
@onready var _ui_coins_container: HBoxContainer = %CoinsContainer
@onready var _ui_text_chat: RoboChat = %Chat
@onready var _ui_weapon: WeaponUI = %WeaponUI
@onready var _step_sound: AudioStreamPlayer3D = $StepSound
@onready var _landing_sound: AudioStreamPlayer3D = $LandingSound
@onready var _game_session_manager: GameSessionManager = get_node("/root/GameSessionManager")

@onready var _start_position: Vector3 = global_transform.origin

var _equipped_weapon: WEAPON_TYPE = WEAPON_TYPE.DEFAULT
var _move_direction: Vector3 = Vector3.ZERO
var _last_strong_direction: Vector3 = Vector3.ZERO
var _gravity: float = -30.0
var _ground_height: float = 0.0
var _coins: int = 0
var _is_on_floor_buffer: bool = false
var _shoot_timer: float = 0.0
var _grenade_timer: float = 0.0

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
var is_just_aiming: bool = false
var is_aiming: bool = false
var is_swapping_weapons: bool = false

var is_using_jumping_pad: bool = false
var is_bouncing: bool = false

var is_frozen: bool = false

func _enter_tree() -> void:
	# Set node authority
	peer_id = int(name)
	local = (peer_id == multiplayer.get_unique_id())
	set_physics_process(local)
	_update_authority()

func _exit_tree() -> void:
	if local:
		MouseHandler.release_mouse_mode(self)

func _ready() -> void:
	if local:
		MouseHandler.request_mouse_mode(self, Input.MOUSE_MODE_CAPTURED, MouseHandler.Priority.GAMEPLAY)
		# Init this value so it doesn't override the spawn rotation
		_last_strong_direction = (_rotation_root.global_transform.basis * Vector3.BACK).normalized()
	_camera_controller.setup(self)

	if _ui_HUD != null:
		_ui_HUD.visible = local
	if local and _ui_weapon != null:
		weapon_switched.connect(_ui_weapon.switch_to)
	_grenade_aim_controller.visible = false
	weapon_switched.emit(WEAPON_TYPE.keys()[0])

	_melee_attack_area.attacker = self
	_melee_attack_area.friendly_fire = friendly_fire

	# If the level isn't loaded yet, freeze the player until it is
	if local and\
		_game_session_manager != null and\
		_game_session_manager.level == null:
		freeze()
		_game_session_manager.level_loaded.connect(_on_level_loaded)

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

func _update_authority():
	# Give authority to this client
	const recursive: bool = false
	set_multiplayer_authority(peer_id, recursive)
	if not recursive:
		if not is_node_ready():
			_client_synchronizer = $ClientSynchronizer
			_grenade_aim_controller = $GrenadeLauncher
		_client_synchronizer.set_multiplayer_authority(peer_id, false)
		_grenade_aim_controller.set_multiplayer_authority(peer_id, false)

func set_multiplayer_data():
	if local and _game_session_manager != null:
		display_name = _game_session_manager.local_player_name
		custom_color = _game_session_manager.local_player_color
	
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
		
		# Enable the text chat if we're the local player coming from a multiplayer lobby
		if _ui_text_chat != null and\
			not RoboLobbyManager.is_singleplayer and\
			_game_session_manager != null and\
			_game_session_manager.connection_mode == GameSessionManager.ConnectionMode.RELAY:
			_ui_text_chat.enable()

func _on_level_loaded(_level_idx: int) -> void:
	unfreeze()
	_game_session_manager.level_loaded.disconnect(_on_level_loaded)

func freeze() -> void:
	is_frozen = true
	velocity = Vector3.ZERO
	set_physics_process(false)

func unfreeze() -> void:
	is_frozen = false
	set_physics_process(local)

func _unhandled_input(event: InputEvent) -> void:
	if not get_window().has_focus():
		return
	
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
		is_just_aiming = event.is_action_pressed("aim")
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
	is_aiming = is_aim_held and (can_shoot_midair or is_on_floor())
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
		if is_just_aiming and not aim_in_camera_direction:
			_camera_controller.set_euler_rotation_y(_rotation_root.global_rotation.y)
		_last_strong_direction = (_camera_controller.global_transform.basis * Vector3.BACK).normalized()

	_orient_character_to_direction(_last_strong_direction, delta)

	# We separate out the y velocity to not interpolate on the gravity
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.lerp(_move_direction * move_speed, acceleration * delta)
	if _move_direction.length() == 0 and velocity.length() < stopping_speed:
		velocity = Vector3.ZERO
	velocity.y = y_velocity

	# Set aiming camera and grenade launcher
	if is_aiming:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.OVER_SHOULDER)
		_grenade_aim_controller.throw_direction = _camera_controller.camera.quaternion * Vector3.FORWARD
		_grenade_aim_controller.from_look_position = _camera_controller.camera.global_position
	else:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.THIRD_PERSON)
		_grenade_aim_controller.throw_direction = _last_strong_direction
		_grenade_aim_controller.from_look_position = global_position

	# Update attack state and position

	_shoot_timer = max(_shoot_timer - delta, 0.0)
	_grenade_timer = max(_grenade_timer - delta, 0.0)

	if is_attacking:
		match _equipped_weapon:
			WEAPON_TYPE.DEFAULT:
				if is_aiming and (can_shoot_midair or is_on_floor()):
					if _shoot_timer <= 0.0:
						_shoot_timer = shoot_cooldown
						shoot()
				elif is_just_attacking:
					attack.rpc()
			WEAPON_TYPE.GRENADE:
				if _grenade_timer <= 0.0:
					_grenade_timer = grenade_cooldown
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
			if not collider.has_method("is_alive") or\
				collider.is_alive():
				if collider.is_in_group("players"):
					# Bounce forward
					bounce_direction = (_last_strong_direction + up_direction).normalized()
				elif collider.is_in_group("enemies"):
					# Bounce away
					bounce_direction = (up_direction - _last_strong_direction).normalized()
					# and lose coins
					lose_coins()

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
	is_just_aiming = false
	is_swapping_weapons = false


@rpc("authority", "call_local", "reliable")
func attack() -> void:
	_attack_animation_player.play("Attack")
	_character_skin.punch()
	# We separate out the y velocity to not override the gravity
	var y_velocity: float = velocity.y
	velocity = _rotation_root.transform.basis * Vector3.BACK * attack_impulse
	velocity.y = y_velocity


func shoot() -> void:
	if not local:
		return
	var origin: Vector3 = global_position + Vector3.UP
	var aim_target: Vector3 = _camera_controller.get_aim_target(distance_limit)
	_spawn_bullet.rpc_id(1, origin, aim_target)


@rpc("authority", "call_local", "reliable")
func _spawn_bullet(origin: Vector3, aim_target: Vector3) -> void:
	var data: Variant = {
		"position": origin,
		"target_position": aim_target,
	}
	Level.spawn_bullet(self, data)


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


func is_alive() -> bool:
	# Currently, the player doesn't have a death state
	return true


func damage(data: Variant) -> void:
	if not is_multiplayer_authority():
		return
	# Always throws character up
	var force: Vector3 = data.get("force", Vector3.ZERO)
	force.y = abs(force.y)
	velocity = force.limit_length(max_throwback_force)
	var can_damage: bool = data.get("can_damage", true)
	if can_damage:
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
