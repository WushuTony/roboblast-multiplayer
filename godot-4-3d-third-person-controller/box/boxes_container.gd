extends Node3D

# Delay the navmesh bake in case multiple boxes gets destroyed in quick succession
const NAVMESH_BAKE_DELAY: float = 0.25

var _boxes: Array[Box] = []
var _navigation_region: NavigationRegion3D = null

var is_pending_navmesh_bake: bool = false
var navmesh_bake_pending_timer: float = 0.0


func _ready():
	set_process(false)
	var parent: Node = get_parent()
	while parent != null:
		if parent is NavigationRegion3D:
			_navigation_region = parent
			break
		parent = parent.get_parent()

	for child in get_children():
		if child is Box:
			child.is_destroyed.connect(on_box_destroyed)
			_boxes.append(child)


func _process(delta: float):
	if is_pending_navmesh_bake and not _navigation_region.is_baking():
		navmesh_bake_pending_timer -= delta
		if navmesh_bake_pending_timer <= 0.0:
			# Rebaking isn't cheap, but avoidance doesn't update the pathfinding
			_navigation_region.bake_navigation_mesh()
			is_pending_navmesh_bake = false
			navmesh_bake_pending_timer = 0.0
			set_process(false)


func on_box_destroyed(_box: Box):
	if _navigation_region == null or not _navigation_region.enabled:
		return

	# If we're already baking, let's wait for it to finish
	if _navigation_region.is_baking():
		await _navigation_region.bake_finished

	is_pending_navmesh_bake = true
	navmesh_bake_pending_timer = NAVMESH_BAKE_DELAY
	set_process(true)
