extends Node3D
class_name Level

@export var display_name: String = "Untitled Level"
@export var world_number: int = 0
@export var level_number: int = 0

@onready var _broken_box_spawner: DynamicSpawner = %BrokenBoxSpawner
@onready var _coin_spawner: DynamicSpawner = %CoinSpawner
@onready var _spawn_points: Node = %SpawnPoints

var spawn_points: Array[Node3D]

static var _instance: Level = null

func _enter_tree() -> void:
	if _instance != null:
		push_error("Level \"" + name + "\" is added to the tree, but we already have another level \"" + _instance.name + "\" loaded. There should only be one!")
	_instance = self

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
	if _instance == self:
		_instance = null

func get_spawn_location(index: int) -> Vector3:
	return spawn_points[index].position

func get_spawn_rotation(index: int) -> Vector3:
	return spawn_points[index].rotation

## This node is meant to attach objects that shouldn't move with their spawner
## (e.g. bullets) or be included in the navmesh rebuild (e.g. broken boxes)
static func get_dynamic_objects_node() -> Node:
	if _instance == null:
		push_error("get_dynamic_objects_node called but there is no level instance")
		return null
	return _instance._get_dynamic_objects_node()

func _get_dynamic_objects_node() -> Node:
	if not is_inside_tree():
		push_error("_get_dynamic_objects_node called but level \"" + name + "\" is not in the scene tree")
		return null
	var dynamic_objects: Node = get_node_or_null("/root/DynamicObjects")
	if dynamic_objects == null:
		dynamic_objects = Node.new()
		dynamic_objects.set_name("DynamicObjects")
		get_tree().get_root().add_child(dynamic_objects)
	return dynamic_objects

## This function is meant to reparent objects that shouldn't move with their spawner
## (e.g. bullets) or be included in the navmesh rebuild (e.g. broken boxes)
static func reparent_target_to_dynamic_objects(target: Node) -> void:
	if _instance == null:
		push_error("reparent_target_to_dynamic_objects called but there is no level instance")
		return
	_instance._reparent_target_to_dynamic_objects(target)

func _reparent_target_to_dynamic_objects(target: Node) -> void:
	var dynamic_objects: Node = _get_dynamic_objects_node()
	if dynamic_objects != null:
		if target.get_parent() != null:
			target.reparent(dynamic_objects)
		else:
			dynamic_objects.add_child(target)

static func spawn_broken_box_with_coins(target_position: Vector3, coins_count: int = 1, coins_collect_delay = 0.5) -> void:
	if _instance == null or not _instance.is_inside_tree():
		push_error("spawn_broken_box_with_coins called but there is no level in the scene tree")
		return
	_instance._spawn_broken_box(target_position)
	if coins_count > 0:
		_instance._spawn_coins(target_position, coins_count, coins_collect_delay)

func _spawn_broken_box(target_position: Vector3) -> void:
	if not is_multiplayer_authority():
		push_error("_spawn_broken_box called but we don't have multiplayer authority")
		return
	var spawn_data: Variant = {
		"position": target_position
	}
	_broken_box_spawner.spawn(spawn_data)

static func spawn_coins(target_position: Vector3, count: int = 1, collect_delay = 0.5) -> void:
	if _instance == null or not _instance.is_inside_tree():
		push_error("spawn_coins called but there is no level in the scene tree")
	_instance._spawn_coins(target_position, count, collect_delay)

func _spawn_coins(target_position: Vector3, count: int = 1, collect_delay = 0.5) -> void:
	if not is_multiplayer_authority():
		push_error("_spawn_coins called but we don't have multiplayer authority")
		return
	var spawn_data: Variant = {
		"position": target_position
	}
	for i in range(count):
		var coin: Coin = _coin_spawner.spawn(spawn_data)
		if coin != null:
			coin.call_deferred("spawn", collect_delay)
