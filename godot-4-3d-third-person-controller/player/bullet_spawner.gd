@tool
extends DynamicSpawner
class_name BulletSpawner

## Speed of shot bullets.
@export var bullet_speed: float = 10.0
## Distance limit after which shot bullets despawn.
@export var distance_limit: float = 14.0
## If projectiles can damage other players/enemies.
@export var friendly_fire: bool = false

func _init() -> void:
	if Engine.is_editor_hint():
		container_name = "Bullets"
		prefix_owner_name = true
		use_custom_spawn = true

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	if use_custom_spawn:
		spawn_function = _custom_bullet_spawn

func shoot(position: Vector3, target_position: Vector3) -> Node:
	var bullet_index: int = get_spawnable_bullet_index()
	if bullet_index < 0:
		return null
	var spawn_data: Variant = {
		"index": bullet_index,
		"position": position,
		"target_position": target_position
	}
	return spawn(spawn_data)

func _custom_bullet_spawn(data: Variant) -> Node:
	var bullet_index: int = data.get("index", -1)
	var bullet_scene: PackedScene = get_bullet_scene(bullet_index)
	if bullet_scene == null:
		return null
	var bullet: Bullet = bullet_scene.instantiate()
	if bullet == null:
		return null
	var position: Vector3 = data.get("position", Vector3.ZERO)
	var target_position: Vector3 = data.get("target_position", Vector3.ZERO)
	_initialise_bullet(bullet, position, target_position)
	return bullet

func _initialise_bullet(bullet: Bullet, position: Vector3, target_position: Vector3) -> void:
	if bullet == null:
		push_error("_initialise_bullet called but there is no bullet")
		return
	bullet.shooter = owner
	bullet.transform.origin = position
	bullet.distance_limit = distance_limit
	var aim_direction: Vector3 = (target_position - position).normalized()
	bullet.velocity = aim_direction * bullet_speed
	bullet.friendly_fire = friendly_fire
	bullet.set_multiplayer_authority(get_multiplayer_authority())

func get_spawnable_bullet_index() -> int:
	if get_spawnable_scene_count() < 1:
		push_error("get_spawnable_bullet_index called but there is no spawnable scene")
		return -1
	
	if get_spawnable_scene_count() == 1:
		return 0
	
	# We have multiple bullet variants, so let's pick a random one.
	var rand_bullet_id: int = randi_range(0, get_spawnable_scene_count() - 1)
	return rand_bullet_id

func get_bullet_scene(index: int) -> PackedScene:
	if index < 0 || index >= get_spawnable_scene_count():
		push_error("get_bullet_scene called but index ", index, " is outside the spawnable range [0,", get_spawnable_scene_count() - 1, "]")
		return null
	var bullet_scene_path: String = get_spawnable_scene(index)
	var bullet_scene: PackedScene = load(bullet_scene_path)
	return bullet_scene
