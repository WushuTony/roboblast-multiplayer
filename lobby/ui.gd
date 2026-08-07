extends CanvasLayer

@onready var _game_session_manager: GameSessionManager = get_parent()
@onready var _enet_address_line_edit: LineEdit = $Start/ENet/Panel/VBox/Options/Address
@onready var _enet_port_spin_box: SpinBox = $Start/ENet/Panel/VBox/Options/Port
@onready var _enet_player_name_line_edit: LineEdit = $Start/ENet/Custom/VBox/Options/Name
@onready var _enet_player_color_picker_button: ColorPickerButton = $Start/ENet/Custom/VBox/Options/ColorPicker
@onready var _lobby_item_list: ItemList = $Start/Relay/List/VBox/HBox/VBox/LobbyList
@onready var _lobby_players_count_item_list: ItemList = $Start/Relay/List/VBox/HBox/VBox2/PlayersList
@onready var _lobby_player_item_list: ItemList = $Start/WaitingRoom/VBox/List/VBox/ItemList
@onready var _lobby_text_chat: RoboChat = $Start/WaitingRoom/VBox/Chat
@onready var _lobby_player_name_line_edit: LineEdit = $Start/WaitingRoom/Split/Custom/VBox/Options/Name
@onready var _lobby_player_color_picker_button: ColorPickerButton = $Start/WaitingRoom/Split/Custom/VBox/Options/ColorPicker

var default_content_scale_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var is_in_menu: bool = false

# This is different from the regex used for the final validation as we need to allow:
# - Fewer characters (for when the player starts typing)
# - A trailing space/dash (as the user might type a word after that)
# - Editing the text without discarding a valid substr (in case a part failed validation)
var _player_name_regex: RegEx = null

var _current_dialog: AcceptDialog = null
var _dialog_lobby_player_product_user_id: String = ""
var _volume_slider: HSlider = null
var _mute_button: Button = null
var _hard_mute_button: Button = null

func _init():
	_player_name_regex = RegEx.create_from_string("([a-zA-Z0-9][ _-]?)*")

func _enter_tree() -> void:
	default_content_scale_mode = get_tree().root.content_scale_mode

func _ready():
	if RoboLobbyManager.is_singleplayer:
		hide()
		return
	
	_on_visibility_changed()
	
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	visibility_changed.connect(_on_visibility_changed)
	$Start/WaitingRoom.hide()
	
	match (_game_session_manager.connection_mode):
		GameSessionManager.ConnectionMode.ENET:
			$Start/ENet.show()
			$Start/WebSocket.hide()
			$Start/Relay.hide()
			_enet_address_line_edit.grab_focus()
			# Initialise the player customisation
			_enet_player_name_line_edit.text = _game_session_manager.local_player_name
			if _game_session_manager.validate_player_color(_game_session_manager.local_player_color):
				_enet_player_color_picker_button.color = _game_session_manager.local_player_color
			# Listen to the player customisation signals
			_enet_player_name_line_edit.text_changed.connect(_on_player_name_changed)
			_enet_player_color_picker_button.color_changed.connect(_on_player_color_changed)
			_enet_player_color_picker_button.picker_created.connect(_on_enet_player_color_picker_created, CONNECT_ONE_SHOT)
			_enet_player_color_picker_button.popup_closed.connect(_on_player_color_picker_closed)
		GameSessionManager.ConnectionMode.WEBSOCKET:
			$Start/ENet.hide()
			$Start/WebSocket.show()
			$Start/Relay.hide()
			$Start/WebSocket/Join/VBox/Options/Url.grab_focus()
		GameSessionManager.ConnectionMode.RELAY:
			$Start/ENet.hide()
			$Start/WebSocket.hide()
			$Start/Relay.show()
			$Start/Relay/List/VBox/Actions/Refresh.grab_focus()
			# Initialise the player customisation
			_lobby_player_name_line_edit.text = _game_session_manager.local_player_name
			if _game_session_manager.validate_player_color(_game_session_manager.local_player_color):
				_lobby_player_color_picker_button.color = _game_session_manager.local_player_color
			# Listen to the player customisation signals
			_lobby_player_name_line_edit.text_changed.connect(_on_lobby_player_name_changed)
			_lobby_player_name_line_edit.text_submitted.connect(_on_lobby_player_name_submitted)
			_lobby_player_color_picker_button.color_changed.connect(_on_player_color_changed)
			_lobby_player_color_picker_button.picker_created.connect(_on_lobby_player_color_picker_created, CONNECT_ONE_SHOT)
			_lobby_player_color_picker_button.popup_closed.connect(_on_player_color_picker_closed)
			# Listen to the lobby manager's signals
			RoboLobbyManager.game_started.connect(_on_game_started)
			# Prepare lobby list
			_load_lobby_list()

func _on_server_disconnected():
	show()

func _on_visibility_changed():
	if visible:
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		is_in_menu = true

# ENet

func _on_enet_join_pressed():
	var address: String = _enet_address_line_edit.text
	var port: int = int(_enet_port_spin_box.value)
	_game_session_manager.start_enet_client(address, port)
	hide()

func _on_enet_host_pressed():
	var port: int = int(_enet_port_spin_box.value)
	_game_session_manager.start_enet_server(port)
	hide()

func _on_enet_player_color_picker_created():
	_on_player_color_picker_created(_enet_player_color_picker_button)

# WebSocket

func _on_websocket_join_pressed():
	var url: String = $Start/WebSocket/Join/VBox/Options/Url.text
	_game_session_manager.start_websocket_client(url)
	hide()

func _on_websocket_host_pressed():
	var port: int = $Start/WebSocket/Host/VBox/Options/Port.value
	_game_session_manager.start_websocket_server(port)
	hide()

# EOS Lobbies

func _load_lobby_list(_page: int = 1) -> void:
	# Query the lobby list API
	var lobby_list: Array[HLobby] = await RoboLobbyManager.query_lobbies_async()
	
	_lobby_item_list.clear()
	_lobby_players_count_item_list.clear()

	if lobby_list == null or lobby_list.is_empty():
		return
	
	# Populate item lists
	for cur_lobby: HLobby in lobby_list:
		var lobby_name_attribute: Variant = cur_lobby.get_attribute("LOBBYNAME")
		var lobby_name: String = lobby_name_attribute.value if (lobby_name_attribute != null and not lobby_name_attribute.is_empty()) else cur_lobby.lobby_id
		var idx: int = _lobby_item_list.add_item(lobby_name)
		_lobby_item_list.set_item_metadata(idx, cur_lobby)
		_lobby_item_list.set_item_tooltip_enabled(idx, false)
		
		var lobby_players: String = str(cur_lobby.members.size(), "/", cur_lobby.max_members)
		idx = _lobby_players_count_item_list.add_item(lobby_players, null, false)
		_lobby_players_count_item_list.set_item_tooltip_enabled(idx, false)

func _on_relay_refresh_pressed() -> void:
	_load_lobby_list()
	# Disable for 3 sec to avoid spamming refresh queries
	$Start/Relay/List/VBox/Actions/Refresh.disabled = true
	await get_tree().create_timer(3.0).timeout
	$Start/Relay/List/VBox/Actions/Refresh.disabled = false

func _on_relay_join_pressed() -> void:
	# Determine the selected lobby
	var selected_items: PackedInt32Array = _lobby_item_list.get_selected_items()
	if selected_items.is_empty():
		return
	var selected_lobby: HLobby = _lobby_item_list.get_item_metadata(selected_items[0])
	if selected_lobby == null or not selected_lobby.is_valid():
		return
	
	# Try to connect
	$Start/Relay.hide()
	if await RoboLobbyManager.join_lobby_async(selected_lobby):
		_init_waiting_room()
	else:
		$Start/Relay.show()

func _on_relay_resolve_pressed() -> void:
	# Get the player input
	var join_code: String = $Start/Relay/Split/Resolve/VBox/HBox/JoinCode.text
	if join_code.is_empty():
		return
	
	# Try to resolve and connect
	$Start/Relay.hide()
	if await RoboLobbyManager.resolve_lobby_async(join_code):
		_init_waiting_room()
	else:
		$Start/Relay.show()

func _on_relay_host_pressed() -> void:
	# Get parameters
	var lobby_name: String = $Start/Relay/Split/Host/VBox/Parameters/Name.text
	var max_players: int = $Start/Relay/Split/Host/VBox/Parameters/MaxPlayers.value
	var visibility_idx: int = $Start/Relay/Split/Host/VBox/Parameters/Visibility.get_selected_id()
	var voice_chat_mode: int = $Start/Relay/Split/Host/VBox/Parameters/VoiceChat.get_selected_id()
	
	# Start a new lobby
	$Start/Relay.hide()
	if await RoboLobbyManager.create_lobby_async(lobby_name, max_players, visibility_idx, voice_chat_mode):
		_init_waiting_room()
	else:
		$Start/Relay.show()

func _init_waiting_room(auto_show: bool = true) -> void:
	if RoboLobbyManager.local_lobby == null:
		return
	
	$Start/WaitingRoom/VBox/List/VBox/Actions/Play.disabled = not RoboLobbyManager.local_lobby.is_owner()
	
	var lobby_name_attribute: Dictionary = RoboLobbyManager.local_lobby.get_attribute("LOBBYNAME")
	var lobby_name: String = lobby_name_attribute.value if (lobby_name_attribute != null and not lobby_name_attribute.is_empty()) else RoboLobbyManager.local_lobby.lobby_id
	$Start/WaitingRoom/Split/Host/VBox/Settings/Name.text = lobby_name
	$Start/WaitingRoom/Split/Host/VBox/Settings/JoinCode.text = RoboLobbyManager.local_lobby.lobby_id
	$Start/WaitingRoom/Split/Host/VBox/Settings/MaxPlayers.value = RoboLobbyManager.local_lobby.max_members
	$Start/WaitingRoom/Split/Host/VBox/Settings/Visibility.select(RoboLobbyManager.local_lobby.permission_level)
	var voice_chat_mode_attribute: Dictionary = RoboLobbyManager.local_lobby.get_attribute("VOICECHATMODE")
	var voice_chat_mode: int = voice_chat_mode_attribute.value if (voice_chat_mode_attribute != null) else 0
	var vc_idx: int = $Start/WaitingRoom/Split/Host/VBox/Settings/VoiceChat.get_item_index(voice_chat_mode)
	$Start/WaitingRoom/Split/Host/VBox/Settings/VoiceChat.select(vc_idx)
	
	if _lobby_text_chat != null:
		_lobby_text_chat.enable()
	
	_update_waiting_room_players()
	var peer: EOSGMultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.peer_connection_established.connect(_on_peer_connection_established)
		peer.peer_connection_closed.connect(_on_peer_connection_closed)
	var local_lobby: HLobby = RoboLobbyManager.local_lobby
	if not local_lobby.lobby_updated.is_connected(_on_lobby_updated):
		local_lobby.lobby_updated.connect(_on_lobby_updated)
	if not local_lobby.kicked_from_lobby.is_connected(_on_kicked_from_lobby):
		local_lobby.kicked_from_lobby.connect(_on_kicked_from_lobby)
	if not local_lobby.lobby_owner_changed.is_connected(_on_lobby_owner_changed):
		local_lobby.lobby_owner_changed.connect(_on_lobby_owner_changed)
	
	if auto_show:
		$Start/WaitingRoom.show()
		if $Start/WaitingRoom/VBox/List/VBox/Actions/Play.disabled:
			$Start/WaitingRoom/VBox/List/VBox/Actions/Leave.grab_focus()
		else:
			$Start/WaitingRoom/VBox/List/VBox/Actions/Play.grab_focus()

func _update_waiting_room_players() -> void:
	_lobby_player_item_list.clear()
	
	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return
	
	# Populate item list
	for cur_player: HLobbyMember in RoboLobbyManager.local_lobby.members:
		var username_attribute: Dictionary = cur_player.get_attribute("USERNAME")
		var username: String = username_attribute.value if (username_attribute != null and not username_attribute.is_empty()) else "Player" + cur_player.product_user_id
		if cur_player.is_owner():
			username += " [Host]"
		elif cur_player.is_self():
			username += " [Self]"
		var idx: int = _lobby_player_item_list.add_item(username)
		_lobby_player_item_list.set_item_metadata(idx, cur_player)
		_lobby_player_item_list.set_item_tooltip_enabled(idx, false)

func _on_peer_connection_established(callback_data: Dictionary) -> void:
	print_verbose("Connection established: ", callback_data)
	_update_waiting_room_players()

func _on_peer_connection_closed(callback_data: Dictionary) -> void:
	print_verbose("Connection closed: ", callback_data)
	_update_waiting_room_players()

func _on_lobby_left() -> void:
	$Start/WaitingRoom.hide()
	if _lobby_text_chat != null:
		_lobby_text_chat.clear()
		_lobby_text_chat.disable()
	$Start/Relay.show()
	$Start/Relay/List/VBox/Actions/Refresh.grab_focus()

func _on_lobby_updated() -> void:
	_update_waiting_room_players()

func _on_kicked_from_lobby() -> void:
	_on_lobby_left()

func _on_lobby_owner_changed() -> void:
	_update_waiting_room_players()
	$Start/WaitingRoom/VBox/List/VBox/Actions/Play.disabled = not RoboLobbyManager.local_lobby.is_owner()
	# The host disconnecting mid-game currently unloads the level, so making sure the UI is displayed
	if not is_in_menu:
		show()

func _on_lobby_player_name_changed(new_name: String):
	# Remember the position of the caret.
	var caret_position: int = _lobby_player_name_line_edit.caret_column

	# Filter the new name according to the regular expession.
	var filtered: String = ""
	for result: RegExMatch in _player_name_regex.search_all(new_name):
		filtered += result.strings[0]

	# If anything was filtered, restore the caret position accordingly.
	if filtered != new_name:
		_lobby_player_name_line_edit.text = filtered
		_lobby_player_name_line_edit.caret_column = caret_position - (new_name.length() - filtered.length())

	_on_player_name_changed(filtered)

func _on_lobby_player_name_submitted(new_name: String):
	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return

	if _game_session_manager == null or not _game_session_manager.validate_player_name(new_name):
		# If the new_name is empty, then lets update anyway, the lobby might want to reset it to its
		# default value.
		if not new_name.is_empty():
			return

	await RoboLobbyManager.update_username_async(new_name)

func _on_lobby_player_color_picker_created() -> void:
	_on_player_color_picker_created(_lobby_player_color_picker_button)

func _on_lobby_player_activated(index: int) -> void:
	var cur_player: HLobbyMember = _lobby_player_item_list.get_item_metadata(index)
	if cur_player == null:
		push_warning("Trying to edit a lobby player that is not valid")
		return

	_current_dialog = AcceptDialog.new()
	_current_dialog.title = _lobby_player_item_list.get_item_text(index)
	_current_dialog.dialog_text = ""
	_dialog_lobby_player_product_user_id = cur_player.product_user_id

	_current_dialog.get_ok_button().hide()

	var volume_container: HBoxContainer = HBoxContainer.new()
	var volume_label: Label = Label.new()
	volume_label.text = "Volume"
	volume_container.add_child(volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.set_value_no_signal(_volume_slider.max_value) # TODO: Get the current volume
	_volume_slider.drag_ended.connect(_on_lobby_player_volume_slider_drag_ended)
	volume_container.add_child(_volume_slider)
	_current_dialog.add_child(volume_container)

	_mute_button = _current_dialog.add_button("Mute")
	_mute_button.text = "Unmute" if cur_player.is_muted() else "Mute"
	_mute_button.pressed.connect(_on_lobby_player_mute_pressed)

	var kick_button: Button = null
	if (RoboLobbyManager.local_lobby != null and
		RoboLobbyManager.local_lobby.is_valid() and
		RoboLobbyManager.local_lobby.is_owner()):
		if not cur_player.is_self():
			_hard_mute_button = _current_dialog.add_button("Hard-mute")
			_hard_mute_button.text = "Un Hard-mute" if cur_player.is_hard_muted() else "Hard-mute"
			_hard_mute_button.pressed.connect(_on_lobby_player_hard_mute_pressed)

			kick_button = _current_dialog.add_button("Kick")
			kick_button.pressed.connect(_on_lobby_player_kick_pressed)

	add_child(_current_dialog)
	
	_mute_button.focus_neighbor_top = _volume_slider.get_path()
	_volume_slider.focus_neighbor_bottom = _mute_button.get_path()
	if _hard_mute_button != null:
		_mute_button.focus_neighbor_left = _hard_mute_button.get_path()
		_hard_mute_button.focus_neighbor_right = _mute_button.get_path()
		if kick_button != null:
			_hard_mute_button.focus_neighbor_left = kick_button.get_path()
			kick_button.focus_neighbor_right = _hard_mute_button.get_path()
	
	_current_dialog.popup_centered(Vector2i(300, 100))
	_current_dialog.unresizable = true
	_current_dialog.show()
	
	_mute_button.grab_focus()

func _on_lobby_player_volume_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return

	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return

	var player_to_change_volume: HLobbyMember = RoboLobbyManager.local_lobby.get_member_by_product_user_id(_dialog_lobby_player_product_user_id)
	if player_to_change_volume == null:
		return

	var new_volume: float = _volume_slider.ratio
	await RoboLobbyManager.set_volume_member_async(player_to_change_volume, new_volume)

func _on_lobby_player_mute_pressed() -> void:
	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return

	var player_to_toggle_mute: HLobbyMember = RoboLobbyManager.local_lobby.get_member_by_product_user_id(_dialog_lobby_player_product_user_id)
	if player_to_toggle_mute == null:
		return

	_mute_button.disabled = true
	if await player_to_toggle_mute.toggle_mute_member_async():
		if _mute_button == null:
			return
		_mute_button.text = "Unmute" if player_to_toggle_mute.is_muted() else "Mute"

	_mute_button.disabled = false

func _on_lobby_player_hard_mute_pressed() -> void:
	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return

	var player_to_toggle_hard_mute: HLobbyMember = RoboLobbyManager.local_lobby.get_member_by_product_user_id(_dialog_lobby_player_product_user_id)
	if player_to_toggle_hard_mute == null:
		return

	_hard_mute_button.disabled = true
	if await player_to_toggle_hard_mute.toggle_hard_mute_member_async():
		if _hard_mute_button == null:
			return
		_hard_mute_button.text = "Un Hard-mute" if player_to_toggle_hard_mute.is_hard_muted() else "Hard-mute"

	_hard_mute_button.disabled = false

func _on_lobby_player_kick_pressed() -> void:
	remove_child(_current_dialog)
	_current_dialog.queue_free()

	if RoboLobbyManager.local_lobby == null or not RoboLobbyManager.local_lobby.is_valid():
		return

	var player_to_kick: HLobbyMember = RoboLobbyManager.local_lobby.get_member_by_product_user_id(_dialog_lobby_player_product_user_id)
	if player_to_kick == null:
		return

	player_to_kick.kick_member_async()

func _on_lobby_leave_pressed() -> void:
	_current_dialog = ConfirmationDialog.new()
	_current_dialog.title = "Leave Lobby"
	_current_dialog.dialog_text = "You are about to leave the lobby, are you sure?"

	_current_dialog.canceled.connect(_on_lobby_leave_canceled)
	_current_dialog.confirmed.connect(_on_lobby_leave_confirmed)

	add_child(_current_dialog)
	_current_dialog.popup_centered()
	_current_dialog.unresizable = true
	_current_dialog.show()

func _on_lobby_leave_canceled() -> void:
	remove_child(_current_dialog)
	_current_dialog.queue_free()

func _on_lobby_leave_confirmed() -> void:
	remove_child(_current_dialog)
	_current_dialog.queue_free()

	if await RoboLobbyManager.leave_async():
		_on_lobby_left()

func _on_lobby_play_pressed() -> void:
	RoboLobbyManager.start_game()

func _on_game_started(_level_idx: int) -> void:
	hide()
	get_tree().root.content_scale_mode = default_content_scale_mode
	is_in_menu = false
	
	# Making sure the lobby username is up-to-date, even if the player didn't submit it
	if RoboLobbyManager.local_username != _lobby_player_name_line_edit.text:
		_on_lobby_player_name_submitted(_lobby_player_name_line_edit.text)

# Player Customisation

func _on_player_name_changed(new_name: String):
	_game_session_manager.local_player_name = new_name

func _on_player_color_changed(new_color: Color):
	_game_session_manager.local_player_color = new_color

func _on_player_color_picker_created(color_picker_button: ColorPickerButton):
	color_picker_button.get_popup().about_to_popup.connect(_on_player_color_picker_opened)
	_on_player_color_picker_opened()

func _on_player_color_picker_opened():
	hide()

func _on_player_color_picker_closed():
	show()
