#class_name RoboLobbyManager
extends Node

@export_file("*.cfg") var eos_credentials_config_path: String = "res://eos_credentials.cfg"
@export_range(2, 64) var max_lobby_members: int = 8

@export_subgroup("Debug")
@export var print_sdk_logs: bool = false

## Emitted for all users when the host of the local lobby starts the game.
signal game_started(level_idx: int)

const BUCKET_ID: String = "quickplay" # For matchmaking
const SOCKET_ID: String = "RoboBlastMP"

enum InitialisationSequence
{
	LOAD_CREDENTIALS,
	INITIALISE_PLATFORM,
	CREATE_PLATFORM,
	LOGIN_ANONYMOUS_USER,
	INITIALISED
}

var local_user_id: String = ""
var _is_initialising: bool = false
var _init_status: InitialisationSequence = InitialisationSequence.LOAD_CREDENTIALS
var _eos_credentials: ConfigFile = null
var _are_sdk_logs_setup: bool = false

var lobby_list: Array[HLobby] = []
var local_lobby: HLobby = null

var is_singleplayer: bool = false

func is_initialised() -> bool:
	return _init_status == InitialisationSequence.INITIALISED

func initialise_async() -> bool:
	if is_initialised() or _is_initialising:
		return is_initialised()

	_is_initialising = true

	# Load the credentials
	if _init_status == InitialisationSequence.LOAD_CREDENTIALS:
		if _eos_credentials == null:
			_eos_credentials = ConfigFile.new()
		var err: Error = _eos_credentials.load(eos_credentials_config_path)
		if err != OK:
			push_error("Failed to load EOS credentials: no config found")
			_is_initialising = false
			return false
		print("Loaded EOS Credentials")
		_init_status = InitialisationSequence.INITIALISE_PLATFORM

	# Initialise the SDK
	if _init_status == InitialisationSequence.INITIALISE_PLATFORM:
		var init_opts = EOS.Platform.InitializeOptions.new()
		var section: String = _eos_credentials.get_sections()[0]
		init_opts.product_name = _eos_credentials.get_value(section, "product_name")
		init_opts.product_version = _eos_credentials.get_value(section, "product_version")

		var init_results = EOS.Platform.PlatformInterface.initialize(init_opts)
		if init_results != EOS.Result.Success:
			push_error("Failed to initialize EOS SDK: " + EOS.result_str(init_results))
			_is_initialising = false
			return false
		print("Initialized EOS Platform")
		_init_status = InitialisationSequence.CREATE_PLATFORM

	# Create EOS platform
	if _init_status == InitialisationSequence.CREATE_PLATFORM:
		var create_opts = EOS.Platform.CreateOptions.new()
		var section: String = _eos_credentials.get_sections()[0]
		create_opts.product_id = _eos_credentials.get_value(section, "product_id")
		create_opts.sandbox_id = _eos_credentials.get_value(section, "sandbox_id")
		create_opts.deployment_id = _eos_credentials.get_value(section, "deployment_id")
		create_opts.client_id = _eos_credentials.get_value(section, "client_id")
		create_opts.client_secret = _eos_credentials.get_value(section, "client_secret")
		create_opts.encryption_key = _eos_credentials.get_value(section, "encryption_key")

		var create_results: bool = EOS.Platform.PlatformInterface.create(create_opts)
		if not create_results:
			push_error("Failed to create EOS Platform")
			_is_initialising = false
			return false
		print("EOS Platform created")
		_init_status = InitialisationSequence.LOGIN_ANONYMOUS_USER
		_eos_credentials = null

	# Setup Logs from EOS
	if print_sdk_logs and not _are_sdk_logs_setup:
		EOS.get_instance().logging_interface_callback.connect(_on_logging_interface_callback)
		var res := EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Info)
		if res != EOS.Result.Success:
			push_warning("Failed to set log level: ", EOS.result_str(res))
		else:
			EOS.get_instance().connect_interface_login_callback.connect(_on_connect_login_callback)
			_are_sdk_logs_setup = true

	if _init_status == InitialisationSequence.LOGIN_ANONYMOUS_USER:
		var new_username: String = "Player#" + str(OS.get_process_id())
		if not await HAuth.login_anonymous_async(new_username):
			push_error("Failed to login as an anonymous user")
			_is_initialising = false
			return false

	_is_initialising = false
	_init_status = InitialisationSequence.INITIALISED
	return true

func _on_logging_interface_callback(msg) -> void:
	msg = EOS.Logging.LogMessage.from(msg) as EOS.Logging.LogMessage
	print("SDK %s | %s" % [msg.category, msg.message])

func _on_exit_game():
	if local_lobby != null:
		if local_lobby.is_owner():
			await local_lobby.destroy_async()
		else:
			await local_lobby.leave_async()

func _exit_tree() -> void:
	_on_exit_game()

func _on_connect_login_callback(data: Dictionary) -> void:
	if not data.success:
		print("Login failed")
		EOS.print_result(data)
		return

	print_rich("[b]Login successfull[/b]: local_user_id=", data.local_user_id)

static func _generate_join_code(length: int = 6) -> String:
	const valid_characters: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456789"
	var result: String = ""
	for i in range(length):
		result += valid_characters[randi() % valid_characters.length()]
	return result

#LOBBY CREATION CODE
#-----------------------------------#
func create_lobby_async(lobby_name: String, max_players: int = -1, visibility: int = 0) -> bool:
	var create_opts: EOS.Lobby.CreateLobbyOptions = EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = BUCKET_ID
	create_opts.max_lobby_members = max_lobby_members if (max_players < 2) else min(max_players, max_lobby_members)
	create_opts.permission_level = clamp(visibility, 0, 2)

	# RTC options for voice/data
	create_opts.enable_rtc_room = true
	create_opts.local_rtc_options = {
		flags = EOS.RTC.JoinRoomFlags.EnableDataChannel
	}

	var new_lobby = await HLobbies.create_lobby_async(create_opts)
	if new_lobby == null:
		printerr("Lobby creation failed")
		return false

	new_lobby.add_attribute("LOBBYNAME", lobby_name)
	var join_code: String = _generate_join_code()
	new_lobby.add_attribute("JOINCODE", join_code)
	new_lobby.add_current_member_attribute("USERNAME", HAuth.display_name)
	if not await new_lobby.update_async():
		printerr("Failed to add attributes to the created lobby")
		return false

	var peer: EOSGMultiplayerPeer = multiplayer.multiplayer_peer if (multiplayer.multiplayer_peer is EOSGMultiplayerPeer) else EOSGMultiplayerPeer.new()
	if not peer.peer_connected.is_connected(_on_peer_connected):
		peer.peer_connected.connect(_on_peer_connected)
	if not peer.peer_disconnected.is_connected(_on_peer_disconnected):
		peer.peer_disconnected.connect(_on_peer_disconnected)

	# Start listening for P2P
	var result := peer.create_server(SOCKET_ID)
	if result != OK:
		printerr("Failed to create server: " + EOS.result_str(result))
		return false

	multiplayer.multiplayer_peer = peer
	local_lobby = new_lobby
	local_lobby.rtc_data_received.connect(_on_rtc_data_received)
	print("Lobby created with join code: " + join_code)
	return true

#LOBBY JOIN CODE
#---------------------------------------#
## Join a lobby
func join_lobby_async(lobby: HLobby) -> bool:
	var new_lobby: HLobby = await HLobbies.join_async(lobby)
	if new_lobby == null:
		return false

	new_lobby.add_current_member_attribute("USERNAME", HAuth.display_name)
	if not await new_lobby.update_async():
		push_warning("Failed to add attributes to the joined lobby")

	return _on_lobby_joined(new_lobby)

func resolve_lobby_async(join_code: String) -> bool:
	var join_code_attribute: Dictionary = HLobby.make_attribute("JOINCODE", join_code.to_upper())
	var search_result: Variant = await HLobbies.search_by_attribute_async(join_code_attribute)
	if (search_result == null or
		not search_result is Array[HLobby] or
		search_result.is_empty()):
		return false

	var lobby: HLobby = search_result[0]
	return await join_lobby_async(lobby)

func _on_lobby_joined(lobby: HLobby) -> bool:
	var peer: EOSGMultiplayerPeer = multiplayer.multiplayer_peer if (multiplayer.multiplayer_peer is EOSGMultiplayerPeer) else EOSGMultiplayerPeer.new()
	if not peer.peer_connected.is_connected(_on_connected_to_server):
		peer.peer_connected.connect(_on_connected_to_server)
	if not peer.peer_connection_closed.is_connected(_on_disconnected_from_server):
		peer.peer_connection_closed.connect(_on_disconnected_from_server)

	var result := peer.create_client(SOCKET_ID, lobby.owner_product_user_id)
	if result != OK:
		printerr("Failed to create client: " + EOS.result_str(result))
		return false

	multiplayer.multiplayer_peer = peer
	local_lobby = lobby
	local_lobby.kicked_from_lobby.connect(_on_kicked_from_lobby)
	local_lobby.rtc_data_received.connect(_on_rtc_data_received)
	return true

## Get public lobbies[br]
## [b]Note:[/b] The list might not be up-to-date, see [b]query_lobbies_async[/b]
func get_lobbies() -> Array[HLobby]:
	return lobby_list

## Search for public lobbies[br]
## [b]Note:[/b] Only call this periodically to get the updated list, otherwise call [b]get_lobbies[/b]
func query_lobbies_async() -> Array[HLobby]:
	var lobbies: Variant = await HLobbies.search_by_bucket_id_async(BUCKET_ID)
	if lobbies != null and lobbies is Array[HLobby]:
		lobby_list = lobbies
	return lobby_list

#LOBBY MANAGEMENT CODE
#-----------------------------------#
func _on_kicked_from_lobby() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

#GAME CODE
#-----------------------------------#
func start_game() -> void:
	# Only the host can start the game
	if local_lobby == null or not local_lobby.is_owner():
		return

	# Make lobby invite-only (hide from searches)
	local_lobby.permission_level = EOS.Lobby.LobbyPermissionLevel.InviteOnly
	if not await local_lobby.update_async():
		push_warning("Failed to make the lobby invite-only")

	# Notify all players via RTC data channel
	var data: Variant = {
		"type": "start_game",
		"level_idx": 0
	}
	var success = local_lobby.rtc_send_data(data)
	if not success:
		push_error("Failed to send start_game message")
		return

	game_started.emit(data.level_idx)

func _on_rtc_data_received(raw_data: PackedByteArray):
	var data: Variant = bytes_to_var(raw_data)
	match (data.type):
		"start_game":
			game_started.emit.call_deferred(data.level_idx)
		_:
			push_warning("RTC data received but type ", data.type, " is not implemented")

func _on_peer_connected(peer_id: int) -> void:
	print("Player %d connected" % peer_id)
	print("User ID: ", (multiplayer.multiplayer_peer as EOSGMultiplayerPeer).get_peer_user_id(peer_id))

func _on_peer_disconnected(peer_id: int) -> void:
	print("Player %d disconnected" % peer_id)
	_on_exit_game()

func _on_connected_to_server(id: int):
	if id == 1:  # Server always has ID 1
		print("Connected to server!")
		print("My peer ID: ", multiplayer.multiplayer_peer.get_unique_id())

func _on_disconnected_from_server(data: Dictionary):
	print("Disconnected from server")
	print("Reason: ", data["reason"])
