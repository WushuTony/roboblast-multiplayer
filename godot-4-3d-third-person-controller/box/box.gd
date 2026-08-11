extends RigidBody3D
class_name Box

## Coins spawned when destroyed
@export var coins_count: int = 5

@onready var _collision_shape: CollisionShape3D = $CollisionShape3d
@onready var _crate_visual: Node3D = $CrateVisual
@onready var _destroy_sound: AudioStreamPlayer3D = $DestroySound

signal on_destroyed(box: Box)


func prepare_destroy(delay: float = 0.5):
	_crate_visual.hide()
	_collision_shape.set_deferred("disabled", true)

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	queue_free()


func damage(_impact_point: Vector3, _force: Vector3):
	_receive_damage.rpc()


@rpc("authority", "call_local", "reliable")
func _receive_damage():
	if multiplayer.is_server():
		Level.spawn_broken_box_with_coins(global_position, coins_count)

	Level.play_sound(_destroy_sound, global_position, randfn(1.0, 0.1))

	prepare_destroy()


func _exit_tree() -> void:
	on_destroyed.emit(self)
