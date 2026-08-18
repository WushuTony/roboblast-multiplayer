extends MultiplayerSpawner
class_name DynamicSpawner
## [b]Automatically replicates runtime-only spawnable nodes from the authority to other multiplayer peers.[/b]
##
## Extends the [MultiplayerSpawner] to handle scenes loading, custom spawn methods, and set the visibility
## of peers dynamically.[br][br]
##
## This is useful to reduce potential lag spikes when first spawning those scenes, specify the position
## (or other parameters) on spawn, and avoid a racing condition when the spawner is part of a scene
## that is loaded asynchronously (e.g. a [Level]).

## Loads the [member MultiplayerSpawner.AutoSpawnList] on startup using threads.[br]
## This reduces potential lag spikes when first spawning those scenes.
@export var auto_load_spawnable_scenes: bool = true
## Use the custom spawn method that takes the first spawnable scene and sets the initial position.
@export var use_custom_spawn: bool = true
## Set the visibility of peer dynamically when the server receives a confirmation that the peer is ready,
## or on spawn if the peer had already confirmed it prior.[br]
## This avoids a racing condition when the spawner is part of a scene that is loaded asynchronously
## (e.g. a [Level]).
@export var use_dynamic_peer_visibility: bool = true
## If [code]true[/code], confirms to the server that the peer is ready to be visible on [member _ready].[br]
## Otherwise, the user needs to manually call [member enable_synchronizers_visibility][code].rpc_id(1)[/code].
@export var auto_confirm_peer_visibility: bool = true

var _cached_packed_scenes: Array[PackedScene] = []
var _server_visible_peer_ids: Array[int] = []

func _init() -> void:
	_cached_packed_scenes.resize(get_spawnable_scene_count())
	if auto_load_spawnable_scenes:
		for i in get_spawnable_scene_count():
			var scene_path: String = get_spawnable_scene(i)
			ResourceLoader.load_threaded_request(scene_path)

func _enter_tree() -> void:
	if use_custom_spawn:
		spawn_function = _custom_spawn

func _ready() -> void:
	if use_dynamic_peer_visibility:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if auto_confirm_peer_visibility:
			enable_synchronizers_visibility.rpc_id(1)

func _on_peer_disconnected(peer_id: int) -> void:
	if use_dynamic_peer_visibility and multiplayer.is_server():
		_server_visible_peer_ids.erase(peer_id)

@rpc("any_peer", "call_local", "reliable")
func enable_synchronizers_visibility() -> void:
	if not use_dynamic_peer_visibility or not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id() if (multiplayer.get_remote_sender_id() != 0) else multiplayer.get_unique_id()
	server_enable_synchronizers_visibility(peer_id)

func server_enable_synchronizers_visibility(peer_id: int) -> void:
	if not use_dynamic_peer_visibility or not multiplayer.is_server():
		return
	var spawn_container: Node = get_spawn_container()
	if spawn_container == null:
		return
	for child: Node in spawn_container.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var sync: MultiplayerSynchronizer = child.get_node("ClientSynchronizer")
		if sync != null:
			print_verbose("[Player %d]: Enabling %s visibility for Player %d" % [multiplayer.get_unique_id(), sync.get_path(), peer_id])
			sync.set_visibility_for(peer_id, true)
	_server_visible_peer_ids.append(peer_id)

@rpc("any_peer", "call_local", "reliable")
func disable_synchronizers_visibility() -> void:
	if not use_dynamic_peer_visibility or not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id() if (multiplayer.get_remote_sender_id() != 0) else multiplayer.get_unique_id()
	server_disable_synchronizers_visibility(peer_id)

func server_disable_synchronizers_visibility(peer_id: int) -> void:
	if not use_dynamic_peer_visibility or not multiplayer.is_server():
		return
	var spawn_container: Node = get_spawn_container()
	if spawn_container == null:
		return
	for child: Node in spawn_container.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var sync: MultiplayerSynchronizer = child.get_node("ClientSynchronizer")
		if sync != null:
			print_verbose("[Player %d]: Disabling %s visibility for Player %d" % [multiplayer.get_unique_id(), sync.get_path(), peer_id])
			sync.set_visibility_for(peer_id, false)
	_server_visible_peer_ids.erase(peer_id)

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
	var spawn_container: Node = get_spawn_container()
	if spawn_container == null:
		return null
	var scene_index: int = data.get("index", 0)
	var scene: PackedScene = _get_spawnable_packed_scene(scene_index)
	if scene == null:
		return null
	var spawned_node: Node3D = scene.instantiate()
	if spawned_node == null:
		return null
	var position: Vector3 = data.get("position", spawned_node.transform.origin)
	var rotation: Vector3 = data.get("rotation", spawned_node.rotation)
	var peer_id: int = data.get("peer_id", 1)
	spawned_node.transform.origin = position
	spawned_node.rotation = rotation
	if use_dynamic_peer_visibility and multiplayer.is_server():
		var sync: MultiplayerSynchronizer = spawned_node.get_node("ClientSynchronizer")
		if sync != null:
			for id in _server_visible_peer_ids:
				sync.set_visibility_for(id, true)
	if peer_id != 1:
		spawned_node.set_multiplayer_authority(peer_id)
	return spawned_node

func get_spawn_container() -> Node:
	return get_node(spawn_path)
