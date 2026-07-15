extends Node3D
class_name Lobby

const PLAYER_SCN: PackedScene = preload("res://godot-4-3d-third-person-controller/player/player.tscn")

const MAX_PLAYERS: int = 2
const DEFAULT_PORT: int = 47218

var headless_mode: bool = (DisplayServer.get_name() == "headless")

var level: Level = null
var level_idx: int = -1

var default_content_scale_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

# Lifecycle

func _enter_tree() -> void:
	if (!headless_mode):
		default_content_scale_mode = get_tree().root.content_scale_mode
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED

func _ready() -> void:
	# Listen to multiplayer signals
	# The following emit on both clients and servers
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# The rest only emit for clients
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Automatically start listening for connections if headless
	if (headless_mode):
		start_enet_server()

# Network

func _start_server_common() -> void:
	# Only spawn a player for the host if not in headless mode
	# Wait for someone to join otherwise before starting the game
	if (!headless_mode):
		get_tree().root.content_scale_mode = default_content_scale_mode
		load_level(0) # start the first level
		spawn_player(1) # server always has ID 1

func _start_client_common() -> void:
	get_tree().root.content_scale_mode = default_content_scale_mode

func start_enet_server(port: int = DEFAULT_PORT) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_server(port, MAX_PLAYERS)
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_start_server_common()

func start_enet_client(address: String, port: int = DEFAULT_PORT) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client(address, port)
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_start_client_common()

func start_websocket_server(port: int = DEFAULT_PORT) -> void:
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	peer.create_server(port)
	multiplayer.multiplayer_peer = peer
	_start_server_common()

func start_websocket_client(url: String) -> void:
	var peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	peer.create_client(url)
	multiplayer.multiplayer_peer = peer
	_start_client_common()

# Network Events

func _on_peer_connected(peer_id: int) -> void:
	# Handle player spawn if hosting
	if (!multiplayer.is_server()): return
	
	# Load the first level if needed
	if (level == null):
		load_level(0)
	
	spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	# Handle player removal if hosting
	if (!multiplayer.is_server()): return
	
	# Unload the level if this is the last player
	if (get_player_count() == 1):
		unload_level()
	
	remove_player(peer_id)

func _on_connected_to_server() -> void:
	pass

func _on_connection_failed() -> void:
	pass

func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	
	default_content_scale_mode = get_tree().root.content_scale_mode
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED

# Level Management

func load_level(new_level_idx: int) -> void:
	# Get level path
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	if (new_level_idx < 0 || new_level_idx >= level_spawner.get_spawnable_scene_count()):
		push_error("Level index out of bounds")
		return
	var level_path: String = level_spawner.get_spawnable_scene(new_level_idx)
	
	# Free previous level
	if (level != null): level.queue_free()
	
	# Load new level
	var level_scn: PackedScene = load(level_path)
	level = level_scn.instantiate()
	level_idx = new_level_idx
	#$Level.add_child.call_deferred(level, true)
	$Level.add_child(level, true)
	
	# Listen to level events
	#level.goal_reached.connect(_on_goal_reached)
	#level.kill_plane_triggered.connect(_on_kill_plane_triggered)
	
	# Teleport players
	#teleport_players(level.get_spawn_position())

func unload_level() -> void:
	if (level != null): level.queue_free()
	level = null
	level_idx = -1

func next_level() -> void:
	if is_final_level():
		return
	load_level(level_idx + 1)

func is_final_level() -> bool:
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	return (level_idx == level_spawner.get_spawnable_scene_count() - 1)

# Level Events

#func _on_goal_reached(_player: Player) -> void:
	## Detect when a player reaches the goal and switch levels
	#if level.players_pending_goal.is_empty():
		#next_level()
#
#func _on_kill_plane_triggered(_player: Player) -> void:
	## Detect when a player reaches the kill plane and teleport them back at the last checkpoint
	#_player.teleport.rpc(level.get_last_checkpoint_position())

# Player Management

func get_player(peer_id: int) -> Player:
	for child: Node in $Players.get_children():
		if (child is Player && child.peer_id == peer_id):
			return child
	return null

func get_players() -> Array[Player]:
	var players: Array[Player] = []
	for child: Node in $Players.get_children():
		if (child is Player):
			players.append(child)
	return players

func get_player_count() -> int:
	var count: int = 0
	for child: Node in $Players.get_children():
		if (child is Player):
			count += 1
	return count

func spawn_player(peer_id: int) -> void:
	# Prepare new player
	var player: Player = PLAYER_SCN.instantiate()
	player.name = str(peer_id)
	
	# Add player to level and teleport to spawn position
	var player_index: int = $Players.get_child_count()
	var spawn_location: Vector3 = level.get_spawn_location(player_index)
	player.transform.origin = spawn_location
	$Players.add_child(player)

func remove_player(peer_id: int) -> void:
	# Find player node
	var player: Player = get_player(peer_id)
	if (player == null): return
	
	# Free player
	player.queue_free()

#func teleport_players(new_pos: Vector3) -> void:
	#for player: Player in get_players():
		#player.teleport.rpc(new_pos)
