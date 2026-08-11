@tool
extends MultiplayerSpawner
class_name DynamicSpawner
## Automatically replicates runtime-only spawnable nodes from the authority to other multiplayer peers.
##
## Extends the MultiplayerSpawner to spawn the nodes in the dynamic objects node.
##
## This is useful to automatically attach the spawned nodes in a path that isn't affected by the spawner's
## parent transform or lifecycle (e.g. a bullet or a broken box).

## The container node's name where the spawned nodes are added as children.[br][br]
## [b]Note:[/b] This should be unique amongst all spawners to avoid name conflicts.
@export var container_name: String = "":
	set(value):
		container_name = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## The owner's name will be added at the start of of the container node's name.[br][br]
## [b]Note:[/b] This allows similar containers to co-exist (e.g. bullet spawners).
@export var prefix_owner_name: bool = false
## Use the custom spawn method that takes the first spawnable scene and sets the initial position.
@export var use_custom_spawn: bool = true
## Loads the [member MultiplayerSpawner.AutoSpawnList] on startup using threads.[br]
## This reduces potential lag spikes when first spawning those scenes.
@export var auto_load_spawnable_scenes: bool = true

var _cached_packed_scenes: Array[PackedScene] = []

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if container_name.is_empty():
		warnings.append("A valid String must be set in the \"Container Name\" property in order for DynamicSpawner to be able to name the container holding the spawned Nodes.")
	
	return warnings

func _init() -> void:
	if Engine.is_editor_hint():
		return
	
	_cached_packed_scenes.resize(get_spawnable_scene_count())
	if auto_load_spawnable_scenes:
		for i in get_spawnable_scene_count():
			var scene_path: String = get_spawnable_scene(i)
			ResourceLoader.load_threaded_request(scene_path)

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		spawn_path = "."
		return
	
	if use_custom_spawn:
		spawn_function = _custom_spawn

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_setup_container.call_deferred()

func _setup_container() -> void:
	var dynamic_objects: Node = Level.get_dynamic_objects_node()
	if dynamic_objects != null:
		var container: Node = Node.new()
		var new_container_name: StringName = _generate_container_name()
		container.set_name(new_container_name)
		dynamic_objects.add_child(container)
		set_spawn_path(container.get_path())
	else:
		await get_tree().create_timer(1.0).timeout
		_setup_container.call_deferred()

func _generate_container_name() -> StringName:
	var new_container_name: StringName = (owner.name + container_name) if (prefix_owner_name) else container_name
	return new_container_name

func _get_spawnable_packed_scene(index: int) -> PackedScene:
	if index < 0 || index >= get_spawnable_scene_count():
		push_error("_get_spawnable_packed_scene called but index ", index, " is outside the spawnable range [0,", get_spawnable_scene_count() - 1, "]")
		return null
	var scene: PackedScene = _cached_packed_scenes[index]
	if scene == null:
		var scene_path: String = get_spawnable_scene(index)
		if auto_load_spawnable_scenes:
			scene = ResourceLoader.load_threaded_get(scene_path)
		else:
			scene = load(scene_path)
		_cached_packed_scenes[index] = scene
	return scene

func _custom_spawn(data: Variant) -> Node:
	var spawn_container: Node = get_node(get_spawn_path())
	if spawn_container == null:
		return null
	var scene: PackedScene = _get_spawnable_packed_scene(0)
	if scene == null:
		return null
	var spawned_node: Node3D = scene.instantiate()
	if spawned_node == null:
		return null
	var position: Vector3 = data.get("position", Vector3.ZERO)
	var peer_id: int = data.get("peer_id", 1)
	spawned_node.transform.origin = position
	spawned_node.set_multiplayer_authority(peer_id)
	return spawned_node

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	var spawn_container: Node = get_node_or_null(get_spawn_path())
	if spawn_container != null:
		spawn_container.queue_free()
