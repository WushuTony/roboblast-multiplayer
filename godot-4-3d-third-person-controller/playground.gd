extends Level

const PLAYER_SCN: PackedScene = preload("res://godot-4-3d-third-person-controller/player/player.tscn")


func _ready() -> void:
	super._ready()
	
	var demo_page: DemoPage = $DemoPage
	if demo_page != null:
		demo_page.resume_demo()
	
	spawn_player.call_deferred(1)


func spawn_player(peer_id: int) -> void:
	# Prepare new player
	var player: Player = PLAYER_SCN.instantiate()
	player.name = str(peer_id)
	
	# Add player to level and teleport to spawn position
	var spawn_location: Vector3 = get_spawn_location(0)
	player.transform.origin = spawn_location
	add_child(player)
