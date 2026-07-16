extends RigidBody3D

const PUFF_SCENE := preload("smoke_puff/smoke_puff.tscn")

## Movement speed when chasing a player
@export var move_speed: float = 3.0
## Delay after losing a player before targeting another one
@export var switch_delay: float = 1.0
## Cooldown between target switch if multiple players are in range but the target becomes unreachable
@export var navigation_switch_cooldown: float = 1.0
## Coins spawned when killed
@export var coins_count: int = 5

@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _beetle_skin: Node3D = $BeetlebotSkin
@onready var _navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _death_collision_shape: CollisionShape3D = $DeathCollisionShape
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound

var _switch_timer: float = 0.0
var _navigation_switch_timer: float = 0.0
var _target_index: int = -1
var _targets: Array[Node3D] = []
var _alive: bool = true


func _ready() -> void:
	if is_multiplayer_authority():
		_navigation_agent.max_speed = move_speed
		set_avoidance_enabled(_navigation_agent.avoidance_enabled)
		_detection_area.body_entered.connect(_on_body_entered)
		_detection_area.body_exited.connect(_on_body_exited)
	else:
		set_physics_process(false)
	_beetle_skin.idle()


func set_avoidance_enabled(enabled: bool) -> void:
	_navigation_agent.avoidance_enabled = enabled
	if enabled:
		if not _navigation_agent.velocity_computed.is_connected(on_velocity_computed):
			_navigation_agent.velocity_computed.connect(on_velocity_computed)
	elif _navigation_agent.velocity_computed.is_connected(on_velocity_computed):
		_navigation_agent.velocity_computed.disconnect(on_velocity_computed)


func _physics_process(delta: float) -> void:
	if not _alive or not is_multiplayer_authority():
		return

	if _target_index < 0:
		_switch_timer = max(_switch_timer - delta, 0.0)
		if _switch_timer <= 0.0 and not _targets.is_empty():
			# We could have a better heuristic (e.g. target the closest player or
			# a player in line of sight), but for now the 1st player detected will do
			_target_index = 0
			_navigation_agent.target_position = _targets[_target_index].global_position
			_found_target.rpc()

	# If we're looking at a player that is out of reach,
	# check if any other player is on the same navmesh
	if _target_index >= 0 and _targets.size() > 1 and not _navigation_agent.is_target_reachable():
		_navigation_switch_timer += delta
		if _navigation_switch_timer >= navigation_switch_cooldown:
			for index in _targets.size():
				if index == _target_index:
					continue
				_navigation_agent.target_position = _targets[index].global_position
				if _navigation_agent.is_target_reachable():
					_target_index = index
					break
			_navigation_switch_timer = 0.0

	var target: Node3D = _targets[_target_index] if (_target_index >= 0 and _target_index < _targets.size()) else null
	if target != null:
		_navigation_agent.target_position = target.global_position
		var target_look_position: Vector3 = target.global_position
		target_look_position.y = global_position.y
		if target_look_position != Vector3.ZERO:
			look_at(target_look_position)

	if _navigation_agent.is_navigation_finished():
		_beetle_skin.idle()
		if not _navigation_agent.is_target_reachable():
			return
		return

	_beetle_skin.walk()
	var next_location := _navigation_agent.get_next_path_position()

	var direction: Vector3 = global_position.direction_to(next_location)
	direction.y = 0
	direction = direction.normalized()

	var new_velocity := direction * move_speed
	if _navigation_agent.avoidance_enabled:
		_navigation_agent.set_velocity(new_velocity)
	else:
		move(new_velocity * delta)


func on_velocity_computed(safe_velocity: Vector3) -> void:
	move(safe_velocity * get_physics_process_delta_time())


func move(motion: Vector3) -> void:
	const test_only: bool = true
	var collision: KinematicCollision3D = move_and_collide(motion, test_only)
	if collision:
		var collider := collision.get_collider()
		if collider is not Player:
			motion = motion.slide(collision.get_normal())
	collision = move_and_collide(motion)
	if collision:
		var collider := collision.get_collider()
		if collider is Player:
			var impact_point: Vector3 = global_position - collider.global_position
			var force := -impact_point
			# Throws player up a little bit
			force.y = 0.5
			force *= 10.0
			collider.damage(impact_point, force)
			_play_attack.rpc()


@rpc("authority", "call_local", "reliable")
func _found_target():
	_reaction_animation_player.play("found_player")


@rpc("authority", "call_local", "reliable")
func _lost_target():
	_reaction_animation_player.play("lost_player")


@rpc("authority", "call_local", "reliable")
func _play_attack():
	_beetle_skin.attack()


func damage(impact_point: Vector3, force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	_receive_damage.rpc(impact_point, force)


@rpc("authority", "call_local", "reliable")
func _receive_damage(impact_point: Vector3, force: Vector3):
	lock_rotation = false
	force = force.limit_length(3.0)
	apply_impulse(force, impact_point)

	if not _alive:
		return

	_defeat_sound.play()
	_alive = false
	_beetle_skin.power_off()
	set_physics_process(false)

	if is_multiplayer_authority():
		_detection_area.body_entered.disconnect(_on_body_entered)
		_detection_area.body_exited.disconnect(_on_body_exited)
	_target_index = -1
	_targets.clear()
	_navigation_agent.target_position = global_position
	set_avoidance_enabled(false)
	_death_collision_shape.set_deferred("disabled", false)

	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false
	gravity_scale = 1.0

	await get_tree().create_timer(2).timeout

	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position
	await puff.full

	if multiplayer.is_server():
		Level.spawn_coins(global_position, coins_count)

	await get_tree().create_timer(0.5).timeout

	queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_targets.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		var body_index: int = _targets.find(body)
		if _target_index == body_index:
			_target_index = -1
			_switch_timer = switch_delay
			_navigation_agent.target_position = global_position
			_lost_target.rpc()
			_beetle_skin.idle()
		elif _target_index > body_index:
			_target_index -= 1
		_targets.remove_at(body_index)
