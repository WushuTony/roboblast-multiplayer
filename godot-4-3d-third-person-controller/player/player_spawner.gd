extends DynamicSpawner
class_name PlayerSpawner

@onready var _game_session_manager: GameSessionManager = get_parent()

func _ready() -> void:
	# Make sure the player spawner can spawn enough players, but not an unlimited amount
	if _game_session_manager != null:
		spawn_limit = _game_session_manager.max_players

func _custom_spawn(data: Variant) -> Node:
	var player: Player = super._custom_spawn(data) as Player
	if player == null:
		push_error("Failed to spawn a player")
		return null
	var rotation: Vector3 = data.get("rotation", Vector3.ZERO)
	var peer_id: int = data.get("peer_id", 1)
	if not rotation.is_zero_approx():
		player.rotation = Vector3.ZERO
		player.get_node("CharacterRotationRoot").rotation = rotation
	player.name = str(peer_id)
	return player

func get_player(peer_id: int) -> Player:
	var players_node: Node = get_spawn_container()
	for child: Node in players_node.get_children():
		if (child is Player && child.peer_id == peer_id):
			return child
	return null

func get_players() -> Array[Player]:
	var players: Array[Player] = []
	var players_node: Node = get_spawn_container()
	for child: Node in players_node.get_children():
		if (child is Player):
			players.append(child)
	return players

func get_player_count() -> int:
	var count: int = 0
	var players_node: Node = get_spawn_container()
	for child: Node in players_node.get_children():
		if (child is Player):
			count += 1
	return count
