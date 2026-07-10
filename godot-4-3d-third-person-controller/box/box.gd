extends RigidBody3D
class_name Box

const COIN_SCENE := preload("../player/coin/coin.tscn")
const DESTROYED_BOX_SCENE := preload("destroyed_box.tscn")

const COINS_COUNT := 5

@onready var _collision_shape: CollisionShape3D = $CollisionShape3d
@onready var _crate_visual: Node3D = $CrateVisual
@onready var _destroy_sound: AudioStreamPlayer3D = $DestroySound

signal is_destroyed(box: Box)


func damage(_impact_point: Vector3, _force: Vector3):
	var dynamic_objects: Node = get_node_or_null("/root/DynamicObjects")
	if dynamic_objects == null:
		dynamic_objects = Node.new()
		dynamic_objects.set_name("DynamicObjects")
		get_tree().get_root().add_child(dynamic_objects)

	for i in range(COINS_COUNT):
		var coin := COIN_SCENE.instantiate()
		dynamic_objects.add_child(coin)
		coin.global_position = global_position
		coin.spawn()

	var destroyed_box := DESTROYED_BOX_SCENE.instantiate()
	dynamic_objects.add_child(destroyed_box)
	destroyed_box.global_position = global_position

	_crate_visual.hide()
	_collision_shape.set_deferred("disabled", true)
	play_destroy_sound(dynamic_objects)

	queue_free()


func play_destroy_sound(new_parent: Node) -> void:
	if new_parent != null:
		# Add it to the parent so it survives after the box is destroyed
		remove_child(_destroy_sound)
		new_parent.add_child(_destroy_sound)

	_destroy_sound.global_position = global_position
	_destroy_sound.pitch_scale = randfn(1.0, 0.1)
	_destroy_sound.play()

	# Tell the sound to delete itself when it is done playing
	_destroy_sound.finished.connect(_destroy_sound.queue_free)

func _exit_tree() -> void:
	is_destroyed.emit(self)
