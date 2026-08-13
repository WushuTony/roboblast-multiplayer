extends Node3D
class_name GrenadeLauncher

@export var min_throw_distance: float = 7.0
@export var max_throw_distance: float = 16.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var from_look_position: Vector3 = Vector3.ZERO
var throw_direction: Vector3 = Vector3.ZERO

@onready var _grenade_spawner: DynamicSpawner = %GrenadeSpawner
@onready var _snap_mesh: Node3D = %SnapMesh
@onready var _raycast: ShapeCast3D = %ShapeCast3D
@onready var _launch_point: Marker3D = %LaunchPoint
@onready var _trail_mesh_instance: MeshInstance3D = %TrailMeshInstance

var _throw_velocity: Vector3 = Vector3.ZERO
var _time_to_land: float = 0.0
var _throw_path_mesh: ImmediateMesh = null


func _ready() -> void:
	_throw_path_mesh = ImmediateMesh.new()
	var parent: CollisionObject3D = get_parent() as CollisionObject3D
	if parent != null:
		_raycast.add_exception_rid(parent.get_rid())
	visibility_changed.connect(_on_visibility_changed)


func _process(_delta: float) -> void:
	if _update_throw_velocity():
		_draw_throw_path()


func _on_visibility_changed() -> void:
	set_process(visible)


func throw_grenade() -> void:
	if not visible:
		return
	_spawn_throw_grenade.rpc_id(1, _launch_point.global_position, _throw_velocity)


@rpc("authority", "call_local", "reliable")
func _spawn_throw_grenade(p_position: Vector3, p_velocity: Vector3) -> void:
	if _grenade_spawner.is_multiplayer_authority():
		var peer_id: int = multiplayer.get_remote_sender_id() if (multiplayer.get_remote_sender_id() != 0) else multiplayer.get_unique_id()
		var _grenade: Grenade = _grenade_spawner.throw(p_position, p_velocity, peer_id)


## Update the velocity to throw grenades and calculate their trajectory[br]
## Returns [code]true[/code] if the velocity changed since the last time it was called
func _update_throw_velocity() -> bool:
	var prev_throw_velocity: Vector3 = _throw_velocity

	var camera: Camera3D = get_viewport().get_camera_3d()
	var up_ratio: float = clamp(max(camera.rotation.x + 0.5, -0.4) * 2, 0.0, 1.0)

	# var throw_direction := camera.quaternion * Vector3.FORWARD
	# If the player's not aiming, the camera's far behind the character, so we increase the ray's
	# length based on how far behind the camera is compared to the character.
	var base_throw_distance: float = lerp(min_throw_distance, max_throw_distance, up_ratio)
	# var camera_forward_distance := camera.global_position.project(throw_direction).distance_to(_launch_point.global_position.project(throw_direction))
	var throw_distance := base_throw_distance #+ camera_forward_distance
	var global_camera_look_position := from_look_position + throw_direction * throw_distance
	_raycast.target_position = global_camera_look_position - _raycast.global_position

	# Snap grenade land position to an enemy the player's aiming at, if applicable
	var to_target := _raycast.target_position

	if _raycast.get_collision_count() != 0:
		var collider: Object = _raycast.get_collider(0)
		var has_target: bool = collider != null and collider.is_in_group("targeteables")
		_snap_mesh.visible = has_target
		if has_target:
			var collision_offset: Vector3 = Vector3.ZERO
			# If the collision shape is offset compared to the collision object,
			# we need to apply that same offset to target them.
			if collider is CollisionObject3D:
				var owner_id: int = collider.shape_find_owner(0)
				var shape_owner: Object = collider.shape_owner_get_owner(owner_id)
				if shape_owner is Node3D:
					collision_offset = shape_owner.position
			to_target = collider.global_position - _launch_point.global_position + collision_offset
			_snap_mesh.global_position = _launch_point.global_position + to_target
			_snap_mesh.look_at(_launch_point.global_position)
	else:
		_snap_mesh.visible = false

	# Calculate the initial velocity the grenade needs based on where we want it to land and how
	# high the curve should go.
	var peak_height: float = max(to_target.y + 0.25, _launch_point.position.y + 0.25)

	var motion_up := peak_height
	var time_going_up := sqrt(2.0 * motion_up / gravity)

	var motion_down := to_target.y - peak_height
	var time_going_down := sqrt(-2.0 * motion_down / gravity)

	_time_to_land = time_going_up + time_going_down

	var target_position_xz_plane := Vector3(to_target.x, 0.0, to_target.z)
	var start_position_xz_plane := Vector3(_launch_point.position.x, 0.0, _launch_point.position.z)

	var forward_velocity := (target_position_xz_plane - start_position_xz_plane) / _time_to_land
	var velocity_up := sqrt(2.0 * gravity * motion_up)

	# Caching the found initial_velocity vector so we can use it on the throw_grenade() function
	_throw_velocity = Vector3.UP * velocity_up + forward_velocity

	return not _throw_velocity.is_equal_approx(prev_throw_velocity)


func _draw_throw_path() -> void:
	const TIME_STEP: float = 0.05
	const TRAIL_WIDTH: float = 0.25

	var forward_direction: Vector3 = Vector3(_throw_velocity.x, 0.0, _throw_velocity.z).normalized()
	var left_direction: Vector3 = Vector3.UP.cross(forward_direction)
	var offset_left: Vector3 = left_direction * TRAIL_WIDTH / 2.0
	var offset_right: Vector3 = -left_direction * TRAIL_WIDTH / 2.0

	_throw_path_mesh.clear_surfaces()
	_throw_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var end_time: float = _time_to_land + 0.5
	var point_previous: Vector3 = Vector3.ZERO
	var time_current: float = 0.0
	# We'll create 2 triangles on each iteration, representing the quad of one
	# section of the path
	while time_current < end_time:
		time_current += TIME_STEP
		var point_current: Vector3 = _throw_velocity * time_current + Vector3.DOWN * gravity * 0.5 * time_current * time_current

		# Our point coordinates are at the center of the path, so we need to calculate vertices
		var trail_point_left_end: Vector3 = point_current + offset_left
		var trail_point_right_end: Vector3 = point_current + offset_right
		var trail_point_left_start: Vector3 = point_previous + offset_left
		var trail_point_right_start: Vector3 = point_previous + offset_right

		# UV position goes from 0 to 1, so we normalize the current iteration
		# to get the progress in the UV texture
		var uv_progress_end: float = time_current / end_time
		var uv_progress_start: float = uv_progress_end - (TIME_STEP / end_time)

		# Left side on the UV texture is at the top of the texture
		# (Vector2(0,1), or Vector2.DOWN). Right side on the UV texture is at
		# the bottom.
		var uv_value_right_start: Vector2 = (Vector2.RIGHT * uv_progress_start)
		var uv_value_right_end: Vector2 = (Vector2.RIGHT * uv_progress_end)
		var uv_value_left_start: Vector2 = Vector2.DOWN + uv_value_right_start
		var uv_value_left_end: Vector2 = Vector2.DOWN + uv_value_right_end

		point_previous = point_current

		# Both triangles need to be drawn in the same orientation (Godot uses
		# clockwise orientation to determine the face normal)

		# Draw first triangle
		_throw_path_mesh.surface_set_uv(uv_value_right_end)
		_throw_path_mesh.surface_add_vertex(trail_point_right_end)
		_throw_path_mesh.surface_set_uv(uv_value_left_start)
		_throw_path_mesh.surface_add_vertex(trail_point_left_start)
		_throw_path_mesh.surface_set_uv(uv_value_left_end)
		_throw_path_mesh.surface_add_vertex(trail_point_left_end)

		# Draw second triangle
		_throw_path_mesh.surface_set_uv(uv_value_right_start)
		_throw_path_mesh.surface_add_vertex(trail_point_right_start)
		_throw_path_mesh.surface_set_uv(uv_value_left_start)
		_throw_path_mesh.surface_add_vertex(trail_point_left_start)
		_throw_path_mesh.surface_set_uv(uv_value_right_end)
		_throw_path_mesh.surface_add_vertex(trail_point_right_end)

	_throw_path_mesh.surface_end()
	_trail_mesh_instance.mesh = _throw_path_mesh
