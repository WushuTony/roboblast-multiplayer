extends RigidBody3D
class_name Bot

const PUFF_SCENE := preload("smoke_puff/smoke_puff.tscn")

## Delay after losing a player before targeting another one
@export var switch_delay: float = 1.0
## Coins spawned when killed
@export var coins_count: int = 5

@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _death_collision_shape: CollisionShape3D = $DeathCollisionShape
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound

var _switch_timer: float = 0.0
var _target_index: int = -1
var _targets: Array[Node3D] = []
var _alive: bool = true

signal on_killed(bot: Bot)


func _ready() -> void:
	if is_multiplayer_authority():
		_detection_area.body_entered.connect(_on_body_entered)
		_detection_area.body_exited.connect(_on_body_exited)


@rpc("authority", "call_local", "reliable")
func _found_target():
	_reaction_animation_player.play("found_player")


@rpc("authority", "call_local", "reliable")
func _lost_target():
	_reaction_animation_player.play("lost_player")


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_targets.append(body)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		var body_index: int = _targets.find(body)
		if _target_index == body_index:
			_reset_target_index()
		elif _target_index > body_index:
			_target_index -= 1
		_targets.remove_at(body_index)


func _reset_target_index() -> void:
	_target_index = -1
	_switch_timer = switch_delay
	_lost_target.rpc()


func damage(impact_point: Vector3, force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	_receive_damage.rpc(impact_point, force)


@rpc("authority", "call_local", "reliable")
func _receive_damage(impact_point: Vector3, force: Vector3) -> void:
	lock_rotation = false
	force = force.limit_length(3.0)
	apply_impulse(force, impact_point)
	_kill_bot()


func _kill_bot() -> void:
	if not _alive:
		return

	_defeat_sound.play()
	_cleanup_dead_bot()
	on_killed.emit(self)

	await get_tree().create_timer(2).timeout

	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position
	await puff.full

	if multiplayer.is_server():
		Level.spawn_coins(global_position, coins_count)

	prepare_destroy()


func _cleanup_dead_bot() -> void:
	if not _alive:
		return

	_alive = false

	if is_multiplayer_authority():
		_detection_area.body_entered.disconnect(_on_body_entered)
		_detection_area.body_exited.disconnect(_on_body_exited)

	_target_index = -1
	_targets.clear()
	_death_collision_shape.set_deferred("disabled", false)

	freeze = false
	gravity_scale = 1.0


func prepare_destroy(delay: float = 0.5):
	hide()
	_cleanup_dead_bot()

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	queue_free()
