extends Node3D
class_name Level

@export var display_name: String = "Untitled Level"
@export var world_number: int = 0
@export var level_number: int = 0

@onready var _spawn_points: Node = %SpawnPoints

var spawn_points: Array[Node3D]

func _ready() -> void:
	for child: Node in _spawn_points.get_children():
		if (child is not Node3D):
			push_warning("Child " + child.name + " in " + _spawn_points.name + " is not a valid spawn point, expecting Node3D")
			continue
		spawn_points.append(child)
	if spawn_points.size() < Lobby.MAX_PLAYERS:
		var missing_spawn_count: int = Lobby.MAX_PLAYERS - spawn_points.size()
		push_error(_spawn_points.name + " is missing " + str(missing_spawn_count) + " child" + ("ren" if (missing_spawn_count > 1) else "") + " Node3D")

func _exit_tree() -> void:
	var dynamic_objects: Node = get_node_or_null("/root/DynamicObjects")
	if dynamic_objects != null:
		dynamic_objects.queue_free()

func get_spawn_location(index: int) -> Vector3:
	return spawn_points[index].position

func get_spawn_rotation(index: int) -> Vector3:
	return spawn_points[index].rotation

# This node is meant to attach objects that shouldn't move with their spawner
# (e.g. bullets) or be included in the navmesh rebuild (e.g. broken boxes)
static func get_dynamic_objects_node(caller: Node) -> Node:
	if caller == null:
		push_error("get_dynamic_objects_node called but the caller node is null")
		return null
	var dynamic_objects: Node = caller.get_node_or_null("/root/DynamicObjects")
	if dynamic_objects == null:
		dynamic_objects = Node.new()
		dynamic_objects.set_name("DynamicObjects")
		caller.get_tree().get_root().add_child(dynamic_objects)
	return dynamic_objects

# This function is meant to reparent objects that shouldn't move with their spawner
# (e.g. bullets) or be included in the navmesh rebuild (e.g. broken boxes)
static func reparent_target_to_dynamic_objects(caller: Node, target: Node) -> void:
	var dynamic_objects: Node = get_dynamic_objects_node(caller)
	if dynamic_objects != null:
		if target.get_parent() != null:
			target.reparent(dynamic_objects)
		else:
			dynamic_objects.add_child(target)
