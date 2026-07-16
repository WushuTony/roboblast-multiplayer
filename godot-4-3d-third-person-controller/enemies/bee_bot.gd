extends RigidBody3D

const PUFF_SCENE := preload("smoke_puff/smoke_puff.tscn")

## Initial delay before shooting the first time after seeing a player
@export var initial_shoot_delay: float = 2.0
## Delay between shoots aimed at a player
@export var shoot_delay: float = 1.5
## Delay after losing a player before targeting another one
@export var switch_delay: float = 1.0
## Coins spawned when killed
@export var coins_count: int = 5

@onready var _bullet_spawner: BulletSpawner = $BulletSpawner
@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _flying_animation_player: AnimationPlayer = $MeshRoot/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _death_mesh_collider: CollisionShape3D = $DeathMeshCollider
@onready var _bee_root: Node3D = $MeshRoot/bee_root
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound

var _shoot_timer: float = 0.0
var _switch_timer: float = 0.0
var _target_index: int = -1
var _targets: Array[Node3D] = []
var _alive: bool = true


func _ready() -> void:
	if is_multiplayer_authority():
		_detection_area.body_entered.connect(_on_body_entered)
		_detection_area.body_exited.connect(_on_body_exited)
	else:
		set_physics_process(false)
	_bee_root.play_idle()


func _physics_process(delta: float) -> void:
	if not _alive or not is_multiplayer_authority():
		return
	
	if _target_index < 0:
		_switch_timer = max(_switch_timer - delta, 0.0)
		if _switch_timer > 0.0:
			return
		
		if _targets.is_empty():
			return
		
		# We could have a better heuristic (e.g. target the closest player or
		# a player in line of sight), but for now the 1st player detected will do
		_shoot_timer = initial_shoot_delay
		_target_index = 0
		_found_target.rpc()
	
	var target: Node3D = _targets[_target_index]
	if target != null:
		var target_transform: Transform3D = transform.looking_at(target.global_position)
		transform = transform.interpolate_with(target_transform, 0.1)

		_shoot_timer -= delta
		if _shoot_timer <= 0.0:
			_play_spit_attack.rpc()
			_shoot_timer = shoot_delay

			var origin: Vector3 = global_position
			var target_position: Vector3 = target.global_position + Vector3.UP
			var _bullet: Bullet = _bullet_spawner.shoot(origin, target_position)


@rpc("authority", "call_local", "reliable")
func _found_target():
	_reaction_animation_player.play("found_player")


@rpc("authority", "call_local", "reliable")
func _lost_target():
	_reaction_animation_player.play("lost_player")


@rpc("authority", "call_local", "reliable")
func _play_spit_attack():
	_bee_root.play_spit_attack()


func damage(impact_point: Vector3, force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	_receive_damage.rpc(impact_point, force)


@rpc("authority", "call_local", "reliable")
func _receive_damage(impact_point: Vector3, force: Vector3):
	force = force.limit_length(3.0)
	apply_impulse(force, impact_point)

	if not _alive:
		return

	_defeat_sound.play()
	_alive = false

	_flying_animation_player.stop()
	_flying_animation_player.seek(0.0, true)
	if is_multiplayer_authority():
		_detection_area.body_entered.disconnect(_on_body_entered)
		_detection_area.body_exited.disconnect(_on_body_exited)
	_target_index = -1
	_targets.clear()
	_death_mesh_collider.set_deferred("disabled", false)
	set_physics_process(false)

	freeze = false
	gravity_scale = 1.0
	_bee_root.play_poweroff()

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
			_lost_target.rpc()
		elif _target_index > body_index:
			_target_index -= 1
		_targets.remove_at(body_index)
