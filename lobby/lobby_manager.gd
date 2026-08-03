#class_name RoboLobbyManager
extends Node

@export_range(2, 64) var max_lobby_members: int = 8

@export_subgroup("Debug")
@export var print_sdk_logs: bool = false

## Emitted for all users when a player sends a text message in the lobby's chat.
signal chat_message_received(username: String, message: String)
## Emitted for all users when the host of the local lobby starts the game.
signal game_started(level_idx: int)

const BUCKET_ID: String = "quickplay" # For matchmaking
const SOCKET_ID: String = "RoboBlastMP"

enum InitialisationSequence
{
	INITIALISE_PLATFORM,
	CREATE_PLATFORM,
	LOGIN_ANONYMOUS_USER,
	INITIALISED
}

enum VoiceChatMode
{
	DISABLED = 0,
	ENABLED_LOBBY_ONLY = 1,
	ENABLED_GAME_ONLY = 2,
	ENABLED_ALL = ENABLED_LOBBY_ONLY | ENABLED_GAME_ONLY
}

var local_user_id: String = ""
var local_username: String = ""
var _is_initialising: bool = false
var _init_status: InitialisationSequence = InitialisationSequence.INITIALISE_PLATFORM
var _are_sdk_logs_setup: bool = false
var _is_shutting_down: bool = false

var lobby_list: Array[HLobby] = []
var local_lobby: HLobby = null

var is_singleplayer: bool = false

func _enter_tree() -> void:
	get_tree().set_auto_accept_quit(false)

func _ready() -> void:
	game_started.connect(_on_game_started)

## Returns [code]true[/code] if the Epic Online Services are initialised
func is_initialised() -> bool:
	return _init_status == InitialisationSequence.INITIALISED

## Initialise Epic Online Services[br]
## Returns [code]true[/code] if the initialisation was successful
func initialise_async() -> bool:
	if is_initialised() or _is_initialising:
		return is_initialised()

	_is_initialising = true

	# Initialise the SDK
	if _init_status == InitialisationSequence.INITIALISE_PLATFORM:
		var init_opts = EOS.Platform.InitializeOptions.new()
		init_opts.product_name = EOSCredentials.PRODUCT_NAME
		init_opts.product_version = EOSCredentials.PRODUCT_VERSION

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
		create_opts.product_id = EOSCredentials.PRODUCT_ID
		create_opts.sandbox_id = EOSCredentials.SANDBOX_ID
		create_opts.deployment_id = EOSCredentials.DEPLOYMENT_ID
		create_opts.client_id = EOSCredentials.CLIENT_ID
		create_opts.client_secret = EOSCredentials.CLIENT_SECRET
		create_opts.encryption_key = EOSCredentials.ENCRYPTION_KEY

		if OS.get_name() == "Windows":
			create_opts.flags = EOS.Platform.PlatformFlags.WindowsEnableOverlayOpengl

		var create_results: bool = EOS.Platform.PlatformInterface.create(create_opts)
		if not create_results:
			push_error("Failed to create EOS Platform")
			_is_initialising = false
			return false
		print("EOS Platform created")
		_init_status = InitialisationSequence.LOGIN_ANONYMOUS_USER

	# Setup Logs from EOS
	if print_sdk_logs and not _are_sdk_logs_setup:
		IEOS.logging_interface_callback.connect(_on_logging_interface_callback)
		var res := EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Info)
		if res != EOS.Result.Success:
			push_warning("Failed to set log level: ", EOS.result_str(res))
		else:
			IEOS.connect_interface_login_callback.connect(_on_connect_login_callback)
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

func _complete_shutdown() -> void:
	EOS.Platform.PlatformInterface.release()

	var res = EOS.Platform.PlatformInterface.shutdown()
	if res != EOS.Result.Success:
		push_error("Failed to shutdown EOS SDK: " + EOS.result_str(res))

	get_tree().quit()

func _safe_shutdown() -> void:
	# Prevent infinite loop if get_tree().quit() is intercepted again
	if _is_shutting_down:
		return
	_is_shutting_down = true

	if local_lobby != null and local_lobby.is_valid():
		leave_async()
		return

	_complete_shutdown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Execute the async shutdown sequence without blocking the main notification frame
		_safe_shutdown()

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
## Create a lobby[br]
## Returns [code]true[/code] if the creation was successful
func create_lobby_async(lobby_name: String, max_players: int = -1, visibility: int = 0, voice_chat_mode: int = 0) -> bool:
	var create_opts: EOS.Lobby.CreateLobbyOptions = EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = BUCKET_ID
	create_opts.max_lobby_members = max_lobby_members if (max_players < 2) else min(max_players, max_lobby_members)
	create_opts.permission_level = clamp(visibility, 0, 2)

	# RTC options for voice/data
	create_opts.enable_rtc_room = true
	if voice_chat_mode == VoiceChatMode.DISABLED:
		create_opts.local_rtc_options = {
			flags = EOS.RTC.JoinRoomFlags.EnableDataChannel,
			use_manual_audio_input = true,  # Manual audio capture
			use_manual_audio_output = true,  # Manual audio playback
			local_audio_device_input_starts_muted = true  # Start muted
		}
	else:
		# A lobby with voice chat cannot exceed 16 players
		create_opts.max_lobby_members = min(create_opts.max_lobby_members, 16)
		create_opts.local_rtc_options = {
			flags = EOS.RTC.JoinRoomFlags.EnableDataChannel,
			use_manual_audio_input = false,  # Automatic audio capture
			use_manual_audio_output = false,  # Automatic audio playback
			local_audio_device_input_starts_muted = false  # Start unmuted
		}

	var new_lobby = await HLobbies.create_lobby_async(create_opts)
	if new_lobby == null:
		printerr("Lobby creation failed")
		return false

	new_lobby.add_attribute("LOBBYNAME", lobby_name)
	var join_code: String = _generate_join_code()
	new_lobby.add_attribute("JOINCODE", join_code)
	new_lobby.add_attribute("VOICECHATMODE", voice_chat_mode)
	var username: String = HAuth.display_name if local_username.is_empty() else local_username
	new_lobby.add_current_member_attribute("USERNAME", username)
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
	local_lobby.kicked_from_lobby.connect(_on_kicked_from_lobby)
	local_lobby.rtc_data_received.connect(_on_rtc_data_received)
	print("Lobby created with join code: " + join_code)
	return true

#LOBBY JOIN CODE
#---------------------------------------#
## Join a lobby[br]
## Returns [code]true[/code] if the join was successful
func join_lobby_async(lobby: HLobby) -> bool:
	# RTC options for voice/data
	var voice_chat_mode_attribute: Dictionary = lobby.get_attribute("VOICECHATMODE")
	var voice_chat_mode: int = voice_chat_mode_attribute.value if (voice_chat_mode_attribute != null) else VoiceChatMode.DISABLED
	if voice_chat_mode == VoiceChatMode.DISABLED:
		HLobbies.local_rtc_options = {
			flags = EOS.RTC.JoinRoomFlags.EnableDataChannel,
			use_manual_audio_input = true,  # Manual audio capture
			use_manual_audio_output = true,  # Manual audio playback
			local_audio_device_input_starts_muted = true  # Start muted
		}
	else:
		HLobbies.local_rtc_options = {
			flags = EOS.RTC.JoinRoomFlags.EnableDataChannel,
			use_manual_audio_input = false,  # Automatic audio capture
			use_manual_audio_output = false,  # Automatic audio playback
			local_audio_device_input_starts_muted = false  # Start unmuted
		}

	var new_lobby: HLobby = await HLobbies.join_async(lobby)
	if new_lobby == null:
		return false

	var username: String = HAuth.display_name if local_username.is_empty() else local_username
	new_lobby.add_current_member_attribute("USERNAME", username)
	if not await new_lobby.update_async():
		push_warning("Failed to add attributes to the joined lobby")

	return _on_lobby_joined(new_lobby)

## Find and join a lobby from its join code[br]
## Returns [code]true[/code] if the join was successful
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
## [b]Note:[/b] The list might not be up-to-date, see [method query_lobbies_async]
func get_lobbies() -> Array[HLobby]:
	return lobby_list

## Search for public lobbies[br]
## [b]Note:[/b] Only call this periodically to get the updated list, otherwise call [method get_lobbies]
func query_lobbies_async() -> Array[HLobby]:
	var lobbies: Variant = await HLobbies.search_by_bucket_id_async(BUCKET_ID)
	if lobbies != null and lobbies is Array[HLobby]:
		lobby_list = lobbies
	return lobby_list

#LOBBY LEAVE CODE
#-----------------------------------#
## Leave the lobby[br]
## Returns [code]true[/code] if the leave was successful
func leave_async() -> bool:
	if local_lobby == null or not local_lobby.is_valid():
		return false

	if (local_lobby.is_owner() and
		(not local_lobby.allow_host_migration or
		local_lobby.members.size() == 1)):
		if not await local_lobby.destroy_async():
			return false
	else:
		if not await local_lobby.leave_async():
			return false

		# Note: destroy_async will kick the player from the lobby, but not leave async,
		# so trigger the relevant cleanup logic here
		_on_kicked_from_lobby()

	return true

func _on_kicked_from_lobby() -> void:
	local_lobby = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	if _is_shutting_down:
		_complete_shutdown.call_deferred()

#LOBBY MEMBER CODE
#-----------------------------------#
## Update the username of the current player in the lobby[br]
## Returns [code]true[/code] if the update was successful
func update_username_async(new_username: String) -> bool:
	if local_lobby == null or not local_lobby.is_valid():
		return false

	# If the new_username is empty, then lets reset it to its default value
	if new_username.is_empty():
		new_username = HAuth.display_name

	local_lobby.add_current_member_attribute("USERNAME", new_username)
	if not await local_lobby.update_async():
		push_error("Failed to update the username of the current player in the lobby")
		return false

	if new_username != HAuth.display_name:
		local_username = new_username
	else:
		local_username = ""
	return true

## Set the audio volume of the specified member[br]
## Returns [code]true[/code] if the logic was successful
func set_volume_member_async(member: HLobbyMember, new_volume: float) -> bool:
	if not member or not local_lobby or not local_lobby.rtc_room_name:
		return false

	member._log.debug("Setting volume to %.2f for member: product_user_id=%s" % [new_volume, member.product_user_id])

	var opts := EOS.RTCAudio.UpdateParticipantVolumeOptions.new()
	opts.room_name = local_lobby.rtc_room_name
	opts.participant_id = member.product_user_id
	opts.volume = new_volume

	EOS.RTCAudio.RTCAudioInterface.update_participant_volume(opts)
	var ret = await IEOS.rtc_audio_interface_update_participant_volume_callback
	if not EOS.is_success(ret):
		member._log.error("Failed to update participant volume: result_code=%s" % EOS.result_str(ret))
		return false

	return true

## Send a chat message to all the players in the lobby[br]
## Emits [signal chat_message_received][br]
## Returns [code]true[/code] if the message was sent successfully
func send_chat_message(message: String) -> bool:
	# Don't send the message if we're not in a lobby or if we're alone
	if local_lobby == null or not local_lobby.is_valid() or local_lobby.members.size() < 2:
		return false

	var username_attribute: Dictionary = local_lobby.get_current_member_attribute("USERNAME")
	var username: String = username_attribute.value if (username_attribute != null and not username_attribute.is_empty()) else "Player" + HAuth.product_user_id
	var data: Variant = {
		"type": "chat",
		"username": username,
		"message": message
	}
	var success: bool = local_lobby.rtc_send_data(data)
	if not success:
		push_error("Failed to send chat message: ", message)
		return false

	chat_message_received.emit.call_deferred(data.username, data.message)
	return true

#GAME CODE
#-----------------------------------#
## Notify all the players in the [member local_lobby] to start the game[br]
## Emits [signal game_started][br]
## [b]Note:[/b] Only the host can start the game (see [method HLobby.is_owner])
func start_game() -> void:
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
	var success: bool = local_lobby.rtc_send_data(data)
	if not success:
		push_error("Failed to send %s message" % data.type)
		return

	game_started.emit(data.level_idx)

func _on_rtc_data_received(raw_data: PackedByteArray):
	var data: Variant = bytes_to_var(raw_data)
	match (data.type):
		"chat":
			chat_message_received.emit.call_deferred(data.username, data.message)
		"start_game":
			game_started.emit.call_deferred(data.level_idx)
		_:
			push_warning("RTC data received but type ", data.type, " is not implemented")

func _on_game_started(_level_idx: int) -> void:
	if local_lobby == null or not local_lobby.is_valid():
		return

	var voice_chat_mode_attribute: Dictionary = local_lobby.get_attribute("VOICECHATMODE")
	var voice_chat_mode: VoiceChatMode = voice_chat_mode_attribute.value
	# If voice chat is enabled in the lobby, but we do not want it in game, leave the RTC room
	if voice_chat_mode == VoiceChatMode.ENABLED_LOBBY_ONLY:
		var leave_room_options = EOS.RTC.LeaveRoomOptions.new()
		leave_room_options.local_user_id = HAuth.product_user_id
		leave_room_options.room_name = local_lobby.rtc_room_name
		EOS.RTC.RTCInterface.leave_room(leave_room_options)

func _on_peer_connected(peer_id: int) -> void:
	print("Player %d connected" % peer_id)
	print("User ID: ", (multiplayer.multiplayer_peer as EOSGMultiplayerPeer).get_peer_user_id(peer_id))

func _on_peer_disconnected(peer_id: int) -> void:
	print("Player %d disconnected" % peer_id)
	if peer_id == multiplayer.get_unique_id():
		leave_async()

func _on_connected_to_server(id: int):
	if id == 1:  # Server always has ID 1
		print("Connected to server!")
		print("My peer ID: ", multiplayer.multiplayer_peer.get_unique_id())

func _on_disconnected_from_server(data: Dictionary):
	print("Disconnected from server")
	print("Reason: ", data["reason"])
