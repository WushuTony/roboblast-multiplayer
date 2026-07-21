class_name Coin
extends RigidBody3D

const MIN_LAUNCH_RANGE := 2.0
const MAX_LAUNCH_RANGE := 4.0
const MIN_LAUNCH_HEIGHT := 1.0
const MAX_LAUNCH_HEIGHT := 3.0

const SPAWN_TWEEN_DURATION := 1.0
const FOLLOW_TWEEN_DURATION := 0.5

@onready var _collect_audio: AudioStreamPlayer3D = $CollectAudio
@onready var _collect_delay: Timer = $CollectDelay
@onready var _player_detection_area: Area3D = $PlayerDetectionArea

var _initial_tween_position: Vector3 = Vector3.ZERO
var _target: Player = null


func spawn(coin_delay: float = 0.5) -> void:
	if not is_multiplayer_authority():
		return

	var rand_height := MIN_LAUNCH_HEIGHT + (randf() * MAX_LAUNCH_HEIGHT)
	var rand_dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * 2 * PI)
	var rand_pos := rand_dir * (MIN_LAUNCH_RANGE + (randf() * MAX_LAUNCH_RANGE))
	rand_pos.y = rand_height
	apply_central_impulse(rand_pos)

	# Delay time for player to be able to collect it
	_collect_delay.timeout.connect(_on_collect_delay_finished)
	_collect_delay.start(coin_delay)
	_player_detection_area.body_entered.connect(_on_body_entered)


func _on_collect_delay_finished() -> void:
	_player_detection_area.monitoring = true
	_player_detection_area.monitorable = true


func set_target(new_target: Player) -> void:
	PhysicsServer3D.body_add_collision_exception(get_rid(), new_target.get_rid())

	if _target == null:
		sleeping = true
		freeze = true

		_initial_tween_position = global_position
		_target = new_target
		var tween := create_tween()
		tween.tween_method(_follow, 0.0, 1.0, 0.5)
		tween.tween_callback(_collect)


func _follow(offset: float) -> void:
	if not is_instance_valid(_target):
		return
	global_position = lerp(_initial_tween_position, _target.global_position, offset)


func _on_body_entered(body: PhysicsBody3D) -> void:
	if _target == null and body is Player:
		set_target(body)


func _collect() -> void:
	if _target == null:
		return
	_collect_for_player.rpc(_target.get_path())


@rpc("authority", "call_local", "reliable")
func _collect_for_player(path : String):
	_collect_audio.pitch_scale = randfn(1.0, 0.1)
	_collect_audio.play()
	
	var target: Player = get_node(path)
	if target != null:
		target.collect_coins()
	
	hide()
	await _collect_audio.finished
	
	if is_multiplayer_authority():
		await get_tree().create_timer(0.5).timeout
		queue_free()
