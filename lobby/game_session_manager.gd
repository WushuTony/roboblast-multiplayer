extends Node3D
class_name GameSessionManager

## Emitted for the local player when a level is loaded.
signal level_loaded(p_level_idx: int)
## Emitted for the local player when a level failed to load.
signal level_load_failed(p_level_idx: int)

## Which connection mode should be used
@export var connection_mode: ConnectionMode = ConnectionMode.RELAY
## Maximum number of players that can play together in the same game world[br]
## [b]Note[/b]: To take into account if the lobby limit is lower, use [method get_max_players] instead
@export_range(2, 64) var max_players: int = 4
@export_file("*.tscn", "*.scn") var level_spawn_list: Array[String] = []
@export var level_spawn_path: NodePath = "Level"
## The path of the config file holding the player settings
@export_global_file("*.cfg") var player_settings_config_file_path: String = "user://configs/player_settings.cfg"

enum ConnectionMode
{
	## Connect via an IP address and port, but only works if all devices are on the same
	## network (see port forwarding / UPnP) and can create security risks
	ENET,
	## Connect via a URL and port, but if a packet drops, it can cause lag spikes as it
	## relies on TCP, is hard to scale, and mobile or unstable networks drop connections easily
	WEBSOCKET,
	## Connect via a lobby, a standard in the industry but if the relay service goes down or
	## experiences an outage, players lose connection even if their local internet is fine
	RELAY
}

@onready var _player_spawner: MultiplayerSpawner = %PlayerSpawner

const DEFAULT_PORT: int = 47218

var headless_mode: bool = (DisplayServer.get_name() == "headless")

var level: Level = null
var level_idx: int = -1
var level_load_idx: int = -1
var level_load_progress: float = 0.0
var _cached_player_scene: PackedScene = null
var has_game_started: bool = false

const PLAYER_CUSTOMISATION_SECTION: String = "Player.Customisation"

var player_name_regex: RegEx = null

var local_player_name: String = "":
	set(new_name):
		if validate_player_name(new_name):
			local_player_name = new_name
var local_player_color: Color = Color.TRANSPARENT:
	set(new_color):
		if validate_player_color(new_color):
			local_player_color = new_color

# Lifecycle

func _init() -> void:
	player_name_regex = RegEx.create_from_string("^(?=.{3,18}$)([a-zA-Z0-9][ _-]?)+[a-zA-Z0-9]$")
	load_player_customisation()

func _ready() -> void:
	set_process(false)
	_load_player_scene_async()
	
	level_loaded.connect(_on_level_loaded)
	level_load_failed.connect(_on_level_load_failed)
	RoboLobbyManager.game_started.connect(_on_game_started)
	RoboLobbyManager.game_ended.connect(_on_game_ended)
	
	# In singleplayer, start the game immediately
	if RoboLobbyManager.is_singleplayer:
		RoboLobbyManager.game_started.emit.call_deferred(0)
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
	_player_spawner.spawn_limit = max_players
	
	# Automatically start listening for connections if headless
	if (headless_mode):
		match (connection_mode):
			ConnectionMode.ENET:
				start_enet_server()
			ConnectionMode.WEBSOCKET:
				start_websocket_server()
			ConnectionMode.RELAY:
				RoboLobbyManager.create_lobby_async("Headless", max_players)

func _process(_delta: float) -> void:
	if (level_load_idx < 0 || level_load_idx >= level_spawn_list.size()):
		push_error("Level index %d is out of bounds" % level_load_idx)
		level_load_failed.emit(level_load_idx)
		return
	
	var scene_path: String = level_spawn_list[level_load_idx]
	var progress: Array[float] = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scene_path, progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("The level %s at index %d is invalid or has not been loaded" % [level_load_idx, scene_path])
			level_load_failed.emit(level_load_idx)
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			level_load_progress = progress[0]
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene = ResourceLoader.load_threaded_get(scene_path)
			_on_level_scene_loaded(scene)
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("Failed to load level %d: %s" % [level_load_idx, scene_path])
			level_load_failed.emit(level_load_idx)

# Network

func _start_server_common() -> void:
	# Only start the game if not in headless mode
	# Otherwise, wait for someone to join first
	if (!headless_mode):
		RoboLobbyManager.game_started.emit.call_deferred(0)

func _start_client_common() -> void:
	RoboLobbyManager.game_started.emit.call_deferred(0)

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
	if not has_game_started:
		return
	
	# If the level is already loaded, we can spawn the player
	if level != null:
		spawn_player(peer_id)
	
	# If a late joiner arrived after the game was started, let them know
	late_join_game_started.rpc_id(peer_id, level_idx)

func _on_peer_disconnected(peer_id: int) -> void:
	if not has_game_started:
		return
	
	remove_player(peer_id)
	
	# End the game if this is the last player, or if the local client / server disconnected
	if get_player_count() == 0\
		or peer_id == multiplayer.get_unique_id()\
		or peer_id == 1:
		RoboLobbyManager.game_ended.emit.call_deferred()

func _on_connected_to_server() -> void:
	pass

func _on_connection_failed() -> void:
	pass

func _on_server_disconnected() -> void:
	# If we have a lobby, let the lobby handle the multiplayer_peer
	if (connection_mode == ConnectionMode.RELAY): return
	
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

# Game Management

@rpc("authority", "call_remote", "reliable")
func late_join_game_started(cur_level_idx: int) -> void:
	RoboLobbyManager.game_started.emit(cur_level_idx)

func _on_game_started(new_level_idx: int = 0) -> void:
	save_player_customisation()
	load_level_async(new_level_idx)
	has_game_started = true

func _on_game_ended() -> void:
	unload_level()
	has_game_started = false

# Level Management

func load_level_async(new_level_idx: int) -> void:
	# Get level scene
	if (new_level_idx < 0 || new_level_idx >= level_spawn_list.size()):
		push_error("Level index %d is out of bounds" % new_level_idx)
		return
	level_load_idx = new_level_idx
	level_load_progress = 0.0
	var scene_path: String = level_spawn_list[new_level_idx]
	ResourceLoader.load_threaded_request(scene_path)
	set_process(true)

## Callback when the level scene is loaded in memory so it can be instantiated
func _on_level_scene_loaded(scene: PackedScene) -> void:
	# Get level node container
	var level_node: Node = _get_level_node_container()
	if level_node == null:
		push_error("No level node container found")
		level_load_failed.emit(level_load_idx)
		return
	
	level_load_progress = 1.0
	set_process(false)
	
	# Free previous level
	if level != null:
		level.queue_free()
		if level.is_queued_for_deletion():
			await get_tree().process_frame
	
	# Load new level
	level = scene.instantiate()
	level_idx = level_load_idx
	level_node.add_child(level, true)
	
	level_loaded.emit(level_idx)

func _on_level_loaded(_p_level_idx: int) -> void:
	if not is_multiplayer_authority():
		return
	
	# Only spawn a player for the host if not in headless mode
	if not headless_mode and multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		spawn_player(peer_id)

func _on_level_load_failed(_p_level_idx: int) -> void:
	level_load_progress = 0.0
	set_process(false)

func unload_level() -> void:
	if level != null:
		level.queue_free()
	level = null
	level_idx = -1

func next_level_async() -> void:
	if is_final_level():
		return
	load_level_async(level_idx + 1)

func is_final_level() -> bool:
	return (level_idx == level_spawn_list.size() - 1)

func _get_level_node_container() -> Node:
	return get_node(level_spawn_path)

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
	if _player_spawner == null or not _player_spawner.is_multiplayer_authority():
		return
	
	# Get player scene
	if _cached_player_scene == null:
		var scene_path: String = _player_spawner.get_spawnable_scene(0)
		_cached_player_scene = ResourceLoader.load_threaded_get(scene_path)
	if _cached_player_scene == null:
		push_error("No player scene to spawn")
		return
	
	# Get player node container
	var players_node: Node = _get_player_node_container()
	if players_node == null:
		push_error("No player node container found")
		return
	
	# Prepare new player
	var player: Player = _cached_player_scene.instantiate()
	player.name = str(peer_id)
	
	# Add player to level and teleport to spawn position
	var player_index: int = players_node.get_child_count()
	var spawn_location: Vector3 = level.get_spawn_location(player_index)
	player.transform.origin = spawn_location
	players_node.add_child(player)

func remove_player(peer_id: int) -> void:
	if _player_spawner == null or not _player_spawner.is_multiplayer_authority():
		return
	
	# Find player node
	var player: Player = get_player(peer_id)
	if player == null:
		return
	
	# Free player
	player.queue_free()

func _get_player_node_container() -> Node:
	return _player_spawner.get_node(_player_spawner.spawn_path)

func _load_player_scene_async() -> void:
	if _player_spawner == null or _player_spawner.get_spawnable_scene_count() < 1:
		push_error("No player scene to spawn")
		return
	if _player_spawner.get_spawnable_scene_count() != 1:
		push_warning(_player_spawner.get_spawnable_scene_count(), " player scenes is not supported, the first one will be picked")
	var scene_path: String = _player_spawner.get_spawnable_scene(0)
	ResourceLoader.load_threaded_request(scene_path)

# Player Customisation

func save_player_customisation() -> void:
	# Making sure the base directory exists before saving
	var base_dir_path: String = player_settings_config_file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir_path):
		var dir_err: Error = DirAccess.make_dir_absolute(base_dir_path)
		if dir_err != OK:
			push_error("Failed to create the player customisation save folder at location \"%s\" with error %s" % [base_dir_path, error_string(dir_err)])
			return

	var config: ConfigFile = ConfigFile.new()

	config.set_value(PLAYER_CUSTOMISATION_SECTION, "Name", local_player_name)
	config.set_value(PLAYER_CUSTOMISATION_SECTION, "Color", local_player_color)

	var err: Error = config.save(player_settings_config_file_path)
	if err != OK:
		push_error("Failed to save the player customisation at location \"%s\" with error %s" % [player_settings_config_file_path, error_string(err)])

func load_player_customisation() -> void:
	var config: ConfigFile = ConfigFile.new()

	var err: Error = config.load(player_settings_config_file_path)
	if err != OK:
		push_warning("Failed to load the player customisation at location \"%s\" with error %s" % [player_settings_config_file_path, error_string(err)])
		return

	if config.has_section(PLAYER_CUSTOMISATION_SECTION):
		local_player_name = config.get_value(PLAYER_CUSTOMISATION_SECTION, "Name")
		local_player_color = config.get_value(PLAYER_CUSTOMISATION_SECTION, "Color")
		if connection_mode == ConnectionMode.RELAY:
			RoboLobbyManager.local_username = local_player_name

func validate_player_name(new_name: String) -> bool:
	var result: RegExMatch = player_name_regex.search(new_name)
	return result != null and result.get_string() == new_name

func validate_player_color(new_color: Color) -> bool:
	return is_equal_approx(new_color.a, 1.0)
