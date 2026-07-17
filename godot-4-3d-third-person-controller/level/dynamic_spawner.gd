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
		update_configuration_warnings()
## The owner's name will be added at the start of of the container node's name.[br][br]
## [b]Note:[/b] This allows similar containers to co-exist (e.g. bullet spawners).
@export var prefix_owner_name: bool = false
## Use the custom spawn method that takes the first spawnable scene and sets the initial position.
@export var use_custom_spawn: bool = true

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if container_name.is_empty():
		warnings.append("A valid String must be set in the \"Container Name\" property in order for DynamicSpawner to be able to name the container holding the spawned Nodes.")
	
	return warnings

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		spawn_path = get_path()
		return
	
	if use_custom_spawn:
		spawn_function = _custom_spawn

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	var dynamic_objects: Node = Level.get_dynamic_objects_node()
	if dynamic_objects != null:
		var container: Node = Node.new()
		var new_container_name: StringName = (owner.name + container_name) if (prefix_owner_name) else container_name
		container.set_name(new_container_name)
		dynamic_objects.add_child(container)
		set_spawn_path(container.get_path())

func _custom_spawn(data: Variant) -> Node:
	var spawn_container: Node = get_node(get_spawn_path())
	if spawn_container == null:
		return null
	var scene_path: String = get_spawnable_scene(0)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return null
	var spawned_node: Node3D = scene.instantiate()
	if spawned_node == null:
		return null
	var position: Vector3 = data.get("position", Vector3.ZERO)
	spawned_node.transform.origin = position
	return spawned_node

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	var spawn_container: Node = get_node_or_null(get_spawn_path())
	if spawn_container != null:
		spawn_container.queue_free()
