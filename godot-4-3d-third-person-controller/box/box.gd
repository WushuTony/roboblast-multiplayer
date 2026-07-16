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

	play_destroy_sound()

	prepare_destroy()


func play_destroy_sound() -> void:
	if not is_instance_valid(_destroy_sound) or _destroy_sound.is_playing():
		return

	# Add it to the dynamic objects so it survives after the box is destroyed
	Level.reparent_target_to_dynamic_objects(_destroy_sound)

	_destroy_sound.global_position = global_position
	_destroy_sound.pitch_scale = randfn(1.0, 0.1)
	_destroy_sound.play()

	# Tell the sound to delete itself when it is done playing
	_destroy_sound.finished.connect(_destroy_sound.queue_free)

func _exit_tree() -> void:
	on_destroyed.emit(self)
