extends PathFollow3D

## Speed of the moving platform
@export var _speed: float = 1.0
## How long should the platform wait at each waypoint in seconds
@export var _pause_time_at_waypoints: float = 0.5
## If enabled, the platform will teleport back at the start when it completed its path
@export var _jump_to_start: bool = false

@onready var _path3D: Path3D = get_parent()

var _total_curve_length: float = 0.0
var _waypoints_count: int = 0
var _waypoint_index: int = 0
var _waypoint_ratios: Array[float] = []

var _moving: bool = false
var _move_from: float = 0.0
var _move_to: float = 0.0
var _move_time: float = 0.0
var _move_delay: float = 0.0
var _move_direction: int = 1 # 1: forward, -1: backward

func _ready() -> void:
	if not is_multiplayer_authority():
		return

	var curve3D: Curve3D = _path3D.curve
	_waypoints_count = curve3D.point_count
	_total_curve_length = curve3D.get_baked_length()
	var cur_length: float = 0.0
	for i in _waypoints_count:
		if i > 0:
			var r1: float = curve3D.get_closest_offset(curve3D.get_point_position(i - 1))
			var r2: float = curve3D.get_closest_offset(curve3D.get_point_position(i))
			cur_length += r2 - r1
		_waypoint_ratios.append(cur_length / _total_curve_length)
		if _waypoint_ratios[i] <= progress_ratio:
			_waypoint_index = i

	if is_equal_approx(_waypoint_ratios[_waypoint_index], progress_ratio):
		_reach_waypoint()
	else:
		_start_move()


func _process(delta: float) -> void:
	if not _moving or not is_multiplayer_authority():
		return

	if _move_delay < _move_time:
		_move_delay += delta
		
		var t: float = _ease_in_out_quart(_move_delay / _move_time) if (_pause_time_at_waypoints > 0) else _move_delay / _move_time
		progress_ratio = lerp(_move_from, _move_to, t)
	else:
		progress_ratio = _move_to
		_moving = false
		
		_reach_waypoint()

func _reach_waypoint() -> void:
	# wait if need be
	if _pause_time_at_waypoints > 0.0:
		await get_tree().create_timer(_pause_time_at_waypoints).timeout
	# restart movement
	_start_move()

func _start_move() -> void:
	_waypoint_index += _move_direction
	if _waypoint_index == _waypoints_count:
		if _jump_to_start:
			_waypoint_index = 1
			progress_ratio = 0.0
		else:
			_move_direction = -1
			_waypoint_index -= 2
	elif _waypoint_index == -1:
		_move_direction = 1
		_waypoint_index += 2

	_move_from = progress_ratio
	_move_to = _waypoint_ratios[_waypoint_index]
	_move_time = abs(_move_to - _move_from) * _total_curve_length / _speed
	_move_delay = 0.0
	_moving = true

func _ease_in_out_quart(x: float) -> float:
	return 8 * x * x * x * x if (x < 0.5) else 1 - pow(-2 * x + 2, 4) / 2
