extends DynamicSpawner
class_name BulletSpawner

func _custom_spawn(data: Variant) -> Node:
	var bullet: Bullet = super._custom_spawn(data) as Bullet
	if bullet == null:
		push_error("Failed to spawn a bullet")
		return null
	_initialise_bullet(bullet, data)
	return bullet

func _initialise_bullet(bullet: Bullet, data: Variant) -> void:
	if bullet == null:
		push_error("_initialise_bullet called but there is no bullet")
		return

	var position: Vector3 = data.get("position", Vector3.ZERO)
	var target_position: Vector3 = data.get("target_position", Vector3.ZERO)
	var shooter_path: NodePath = data.get("shooter", "")

	var shooter: Node = get_node(shooter_path)
	bullet.shooter = shooter
	var aim_direction: Vector3 = (target_position - position).normalized()
	bullet.velocity = aim_direction
	if shooter != null and shooter.is_in_group("shooters"):
		bullet.distance_limit = shooter.distance_limit
		bullet.velocity *= shooter.bullet_speed
		bullet.friendly_fire = shooter.friendly_fire
	else:
		push_error("_initialise_bullet called but the shooter is invalid or not part of the \"shooters\" group")

func get_spawnable_bullet_index() -> int:
	if get_spawnable_scene_count() < 1:
		push_error("get_spawnable_bullet_index called but there is no spawnable scene")
		return -1
	
	if get_spawnable_scene_count() == 1:
		return 0
	
	# We have multiple bullet variants, so let's pick a random one.
	var rand_bullet_id: int = randi_range(0, get_spawnable_scene_count() - 1)
	return rand_bullet_id
