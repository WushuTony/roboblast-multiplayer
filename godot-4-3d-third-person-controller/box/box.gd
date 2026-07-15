extends RigidBody3D
class_name Box

const COIN_SCENE := preload("../player/coin/coin.tscn")
const DESTROYED_BOX_SCENE := preload("destroyed_box.tscn")

const COINS_COUNT := 5

@onready var _collision_shape: CollisionShape3D = $CollisionShape3d
@onready var _crate_visual: Node3D = $CrateVisual
@onready var _destroy_sound: AudioStreamPlayer3D = $DestroySound

signal on_destroyed(box: Box)


func prepare_destroy():
	_crate_visual.hide()
	_collision_shape.set_deferred("disabled", true)

	await get_tree().create_timer(0.5).timeout

	queue_free()


func damage(_impact_point: Vector3, _force: Vector3):
	_receive_damage.rpc()


@rpc("authority", "call_local", "reliable")
func _receive_damage():
	var dynamic_objects: Node = Level.get_dynamic_objects_node(self)

	# TODO: Make a multiplayer spawner for coins
	for i in range(COINS_COUNT):
		var coin := COIN_SCENE.instantiate()
		dynamic_objects.add_child(coin)
		coin.global_position = global_position
		coin.spawn()

	# TODO: Make a multiplayer spawner for destroyed boxes
	var destroyed_box := DESTROYED_BOX_SCENE.instantiate()
	dynamic_objects.add_child(destroyed_box)
	destroyed_box.global_position = global_position

	play_destroy_sound(dynamic_objects)

	prepare_destroy()


func play_destroy_sound(new_parent: Node) -> void:
	if not is_instance_valid(_destroy_sound) or _destroy_sound.is_playing():
		return

	if new_parent != null:
		# Add it to the parent so it survives after the box is destroyed
		_destroy_sound.reparent(new_parent)

	_destroy_sound.global_position = global_position
	_destroy_sound.pitch_scale = randfn(1.0, 0.1)
	_destroy_sound.play()

	# Tell the sound to delete itself when it is done playing
	_destroy_sound.finished.connect(_destroy_sound.queue_free)

func _exit_tree() -> void:
	on_destroyed.emit(self)
