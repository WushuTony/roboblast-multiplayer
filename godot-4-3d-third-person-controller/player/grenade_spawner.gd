extends DynamicSpawner
class_name GrenadeSpawner

func _custom_spawn(data: Variant) -> Node:
	var grenade: Grenade = super._custom_spawn(data) as Grenade
	if grenade == null:
		push_error("Failed to spawn a grenade")
		return null
	_initialise_grenade(grenade, data)
	return grenade

func _initialise_grenade(grenade: Grenade, data: Variant) -> void:
	if grenade == null:
		push_error("_initialise_grenade called but there is no grenade")
		return

	var velocity: Vector3 = data.get("velocity", Vector3.ZERO)
	var grenade_launcher_path: NodePath = data.get("grenade_launcher", "")

	grenade._velocity = velocity
	var grenade_launcher: GrenadeLauncher = get_node(grenade_launcher_path)
	if grenade_launcher != null:
		grenade.shooter = grenade_launcher.owner
		if grenade.shooter != null:
			PhysicsServer3D.body_add_collision_exception(grenade.shooter.get_rid(), grenade.get_rid())
		grenade.gravity = grenade_launcher.gravity
		grenade.friendly_fire = grenade_launcher.friendly_fire
		grenade.damage_self = grenade_launcher.damage_self
	else:
		push_error("_initialise_grenade called but there is no grenade_launcher")

func get_spawnable_grenade_index() -> int:
	if get_spawnable_scene_count() < 1:
		push_error("get_spawnable_grenade_index called but there is no spawnable scene")
		return -1
	
	if get_spawnable_scene_count() == 1:
		return 0
	
	# We have multiple grenade variants, so let's pick a random one.
	var rand_grenade_id: int = randi_range(0, get_spawnable_scene_count() - 1)
	return rand_grenade_id
