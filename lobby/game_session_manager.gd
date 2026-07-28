extends Node3D
class_name GameSessionManager

## Which connection mode should be used[br]
## [b]ENet[/b]: Connect via an IP address and port, but only works if all devices are on the same
## network (see port forwarding / UPnP) and can create security risks[br]
## [b]WebSocket[/b]: Connect via a URL and port, but if a packet drops, it can cause lag spikes as it
## relies on TCP, is hard to scale, and mobile or unstable networks drop connections easily[br]
## [b]Relay[/b]: Connect via a lobby, a standard in the industry but if the relay service goes down or
## experiences an outage, players lose connection even if their local internet is fine[br]
@export_enum("ENet", "WebSocket", "Relay") var connection_mode: int = 2
## Maximum number of players that can play together in the same game world[br]
## [b]Note[/b]: To take into account if the lobby limit is lower, use [method get_max_players] instead
@export_range(2, 64) var max_players: int = 4

const DEFAULT_PORT: int = 47218

var headless_mode: bool = (DisplayServer.get_name() == "headless")

var level: Level = null
var level_idx: int = -1

var default_content_scale_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

var local_player_name: String = ""
var local_player_color: Color = Color.TRANSPARENT

# Lifecycle

func _enter_tree() -> void:
	if (!headless_mode):
		default_content_scale_mode = get_tree().root.content_scale_mode
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED

func _ready() -> void:
	# In singleplayer, start the game immediately
	if RoboLobbyManager.is_singleplayer:
		_on_game_started()
		return
	
	# Listen to multiplayer signals
	# The following emit on both clients and servers
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# The rest only emit for clients
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Make sure the player spawner can spawn enough players
	var player_spawner: MultiplayerSpawner = $PlayerSpawner
	player_spawner.spawn_limit = max_players
	
	# In relay mode, listen to the lobby manager's signals
	if connection_mode == 2:
		RoboLobbyManager.game_started.connect(_on_game_started)
	
	# Automatically start listening for connections if headless
	if (headless_mode):
		match (connection_mode):
			0: # ENet
				start_enet_server()
			1: # WebSocket
				start_websocket_server()
			2: # Relay
				RoboLobbyManager.create_lobby_async("Headless", max_players)

# Network

func _start_server_common() -> void:
	# Only start the game if not in headless mode
	# Otherwise, wait for someone to join first
	if (!headless_mode):
		_on_game_started()

func _start_client_common() -> void:
	_on_game_started()

func start_enet_server(port: int = DEFAULT_PORT) -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_server(port, max_players)
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
	# If we have a lobby, don't load a level immediately
	if (connection_mode == 2): return
	
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

# Game Management

func _on_game_started(new_level_idx: int = 0) -> void:
	get_tree().root.content_scale_mode = default_content_scale_mode
	if is_multiplayer_authority():
		load_level(new_level_idx)
		# Only spawn a player for the host if not in headless mode
		if !headless_mode and multiplayer.is_server():
			spawn_player(multiplayer.get_unique_id())
		for peer_id in multiplayer.get_peers():
			spawn_player(peer_id)

# Level Management

func load_level(new_level_idx: int) -> void:
	if not is_multiplayer_authority():
		return
	
	# Get level scene
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	if (new_level_idx < 0 || new_level_idx >= level_spawner.get_spawnable_scene_count()):
		push_error("Level index out of bounds")
		return
	var scene_path: String = level_spawner.get_spawnable_scene(new_level_idx)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("No level scene to spawn at index ", new_level_idx)
		return
	
	# Get level node container
	var level_node: Node = _get_level_node_container()
	if level_node == null:
		push_error("No level node container found")
		return
	
	# Free previous level
	if (level != null):
		level_node.remove_child(level)
		level.queue_free()
	
	# Load new level
	level = scene.instantiate()
	level_idx = new_level_idx
	level_node.add_child(level, true)

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

func _get_level_node_container() -> Node:
	var level_spawner: MultiplayerSpawner = $LevelSpawner
	return level_spawner.get_node(level_spawner.spawn_path)

# Player Management

func get_max_players() -> int:
	if RoboLobbyManager.local_lobby != null:
		return min(max_players, RoboLobbyManager.local_lobby.max_members)
	return max_players

func get_player(peer_id: int) -> Player:
	var players_node: Node = _get_player_node_container()
	for child: Node in players_node.get_children():
		if (child is Player && child.peer_id == peer_id):
			return child
	return null

func get_players() -> Array[Player]:
	var players: Array[Player] = []
	var players_node: Node = _get_player_node_container()
	for child: Node in players_node.get_children():
		if (child is Player):
			players.append(child)
	return players

func get_player_count() -> int:
	var count: int = 0
	var players_node: Node = _get_player_node_container()
	for child: Node in players_node.get_children():
		if (child is Player):
			count += 1
	return count

func spawn_player(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	
	# Get player scene
	var player_spawner: MultiplayerSpawner = $PlayerSpawner
	if (player_spawner.get_spawnable_scene_count() < 1):
		push_error("No player scene to spawn")
		return
	if (player_spawner.get_spawnable_scene_count() != 1):
		push_warning(player_spawner.get_spawnable_scene_count(), " player scenes is not supported, the first one will be picked")
	var scene_path: String = player_spawner.get_spawnable_scene(0)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("No player scene to spawn")
		return
	
	# Get player node container
	var players_node: Node = _get_player_node_container()
	if players_node == null:
		push_error("No player node container found")
		return
	
	# Prepare new player
	var player: Player = scene.instantiate()
	player.name = str(peer_id)
	
	# Add player to level and teleport to spawn position
	var player_index: int = players_node.get_child_count()
	var spawn_location: Vector3 = level.get_spawn_location(player_index)
	player.transform.origin = spawn_location
	players_node.add_child(player)

func remove_player(peer_id: int) -> void:
	# Find player node
	var player: Player = get_player(peer_id)
	if (player == null): return
	
	# Free player
	player.queue_free()

func _get_player_node_container() -> Node:
	var player_spawner: MultiplayerSpawner = $PlayerSpawner
	return player_spawner.get_node(player_spawner.spawn_path)
