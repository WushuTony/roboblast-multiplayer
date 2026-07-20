@tool
extends DynamicSpawner
class_name GrenadeSpawner

## If grenades can damage other players/enemies.
@export var friendly_fire: bool = false

@onready var _grenade_launcher: GrenadeLauncher = owner

func _init() -> void:
	if Engine.is_editor_hint():
		container_name = "Grenades"
		prefix_owner_name = true
		use_custom_spawn = true

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	if use_custom_spawn:
		spawn_function = _custom_grenade_spawn

func _generate_container_name() -> StringName:
	var new_container_name: StringName = (_grenade_launcher.get_owner().name + container_name) if (prefix_owner_name) else container_name
	return new_container_name

func throw(position: Vector3, velocity: Vector3) -> Node:
	var grenade_index: int = get_spawnable_grenade_index()
	if grenade_index < 0:
		return null
	var spawn_data: Variant = {
		"index": grenade_index,
		"position": position,
		"velocity": velocity
	}
	return spawn(spawn_data)

func _custom_grenade_spawn(data: Variant) -> Node:
	var grenade_index: int = data.get("index", -1)
	var grenade_scene: PackedScene = get_grenade_scene(grenade_index)
	if grenade_scene == null:
		return null
	var grenade: Grenade = grenade_scene.instantiate()
	if grenade == null:
		return null
	var position: Vector3 = data.get("position", Vector3.ZERO)
	var velocity: Vector3 = data.get("velocity", Vector3.ZERO)
	_initialise_grenade(grenade, position, velocity)
	return grenade

func _initialise_grenade(grenade: Grenade, position: Vector3, velocity: Vector3) -> void:
	if grenade == null:
		push_error("_initialise_grenade called but there is no grenade")
		return
	grenade.shooter = _grenade_launcher.get_owner()
	if grenade.shooter != null:
		PhysicsServer3D.body_add_collision_exception(grenade.shooter.get_rid(), grenade.get_rid())
	grenade.transform.origin = position
	grenade._velocity = velocity
	grenade.friendly_fire = friendly_fire
	grenade.set_multiplayer_authority(get_multiplayer_authority())

func get_spawnable_grenade_index() -> int:
	if get_spawnable_scene_count() < 1:
		push_error("get_spawnable_grenade_index called but there is no spawnable scene")
		return -1
	
	if get_spawnable_scene_count() == 1:
		return 0
	
	# We have multiple grenade variants, so let's pick a random one.
	var rand_grenade_id: int = randi_range(0, get_spawnable_scene_count() - 1)
	return rand_grenade_id

func get_grenade_scene(index: int) -> PackedScene:
	if index < 0 || index >= get_spawnable_scene_count():
		push_error("get_grenade_scene called but index ", index, " is outside the spawnable range [0,", get_spawnable_scene_count() - 1, "]")
		return null
	var grenade_scene_path: String = get_spawnable_scene(index)
	var grenade_scene: PackedScene = load(grenade_scene_path)
	return grenade_scene
