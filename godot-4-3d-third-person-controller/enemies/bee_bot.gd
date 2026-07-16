extends Bot
class_name BeeBot

## Initial delay before shooting the first time after seeing a player
@export var initial_shoot_delay: float = 2.0
## Delay between shoots aimed at a player
@export var shoot_delay: float = 1.5

@onready var _bullet_spawner: BulletSpawner = $BulletSpawner
@onready var _flying_animation_player: AnimationPlayer = $MeshRoot/AnimationPlayer
@onready var _bee_root: Node3D = $MeshRoot/bee_root

var _shoot_timer: float = 0.0


func _ready() -> void:
	super._ready()

	if not is_multiplayer_authority():
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
func _play_spit_attack():
	_bee_root.play_spit_attack()


func _cleanup_dead_bot() -> void:
	if not _alive:
		return

	super._cleanup_dead_bot()

	set_physics_process(false)

	_flying_animation_player.stop()
	_flying_animation_player.seek(0.0, true)

	_bee_root.play_poweroff()
