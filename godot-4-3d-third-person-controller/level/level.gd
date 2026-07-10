extends Node3D
class_name Level

@export var display_name: String = "Untitled Level"
@export var world_number: int = 0
@export var level_number: int = 0

@onready var _spawn_points: Node = $SpawnPoints

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

func get_spawn_location(index: int) -> Vector3:
	return spawn_points[index].position

func get_spawn_rotation(index: int) -> Vector3:
	return spawn_points[index].rotation
