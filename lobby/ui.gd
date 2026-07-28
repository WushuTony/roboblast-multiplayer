extends CanvasLayer

@onready var _game_session_manager: GameSessionManager = get_parent()
@onready var _enet_address_line_edit: LineEdit = $Start/ENet/Panel/VBox/Options/Address
@onready var _enet_port_spin_box: SpinBox = $Start/ENet/Panel/VBox/Options/Port
@onready var _enet_player_name_line_edit: LineEdit = $Start/ENet/Custom/VBox/Options/Name
@onready var _enet_player_color_picker_button: ColorPickerButton = $Start/ENet/Custom/VBox/Options/ColorPicker
@onready var _lobby_player_name_line_edit: LineEdit = $Start/WaitingRoom/Split/Custom/VBox/Options/Name
@onready var _lobby_player_color_picker_button: ColorPickerButton = $Start/WaitingRoom/Split/Custom/VBox/Options/ColorPicker

func _ready():
	if RoboLobbyManager.is_singleplayer:
		hide()
		return
	
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	$Start/WaitingRoom.hide()
	
	match (_game_session_manager.connection_mode):
		0: # ENet
			$Start/ENet.show()
			$Start/WebSocket.hide()
			$Start/Relay.hide()
			# Listen to the player customisation signals
			_enet_player_name_line_edit.text_changed.connect(_on_player_name_changed)
			_enet_player_color_picker_button.color_changed.connect(_on_player_color_changed)
			_enet_player_color_picker_button.picker_created.connect(_on_enet_player_color_picker_created, CONNECT_ONE_SHOT)
			_enet_player_color_picker_button.popup_closed.connect(_on_player_color_picker_closed)
		1: # WebSocket
			$Start/ENet.hide()
			$Start/WebSocket.show()
			$Start/Relay.hide()
		2: # Relay
			$Start/ENet.hide()
			$Start/WebSocket.hide()
			$Start/Relay.show()
			# Listen to the player customisation signals
			_lobby_player_name_line_edit.text_changed.connect(_on_player_name_changed)
			_lobby_player_color_picker_button.color_changed.connect(_on_player_color_changed)
			_lobby_player_color_picker_button.picker_created.connect(_on_lobby_player_color_picker_created, CONNECT_ONE_SHOT)
			_lobby_player_color_picker_button.popup_closed.connect(_on_player_color_picker_closed)
			# Listen to the lobby manager's signals
			RoboLobbyManager.game_started.connect(_on_game_started)
			# Prepare lobby list
			_load_lobby_list()

func _on_server_disconnected():
	show()

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
	
	if lobby_list == null or lobby_list.is_empty():
		return
	
	# Populate item list
	var item_list: ItemList = $Start/Relay/List/VBox/ItemList
	item_list.clear()
	for cur_lobby: HLobby in lobby_list:
		var lobby_name_attribute: Variant = cur_lobby.get_attribute("LOBBYNAME")
		var lobby_name: String = lobby_name_attribute.value if (lobby_name_attribute != null and not lobby_name_attribute.is_empty()) else cur_lobby.lobby_id
		item_list.add_item(lobby_name)

func _on_relay_refresh_pressed() -> void:
	_load_lobby_list()
	# Disable for 3 sec to avoid spamming refresh queries
	$Start/Relay/List/VBox/Actions/Refresh.disabled = true
	await get_tree().create_timer(3.0).timeout
	$Start/Relay/List/VBox/Actions/Refresh.disabled = false

func _on_relay_join_pressed() -> void:
	# Determine the selected lobby
	var selected_items: PackedInt32Array = $Start/Relay/List/VBox/ItemList.get_selected_items()
	if selected_items.is_empty():
		return
	var lobby_list: Array[HLobby] = RoboLobbyManager.get_lobbies()
	if lobby_list == null or selected_items[0] >= lobby_list.size():
		return
	var selected_lobby: HLobby = lobby_list[selected_items[0]]
	
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
	if lobby_name.is_empty():
		return
	var max_players: int = $Start/Relay/Split/Host/VBox/Parameters/MaxPlayers.value
	var visibility_idx: int = $Start/Relay/Split/Host/VBox/Parameters/Visibility.get_selected_id()
	
	# Start a new lobby
	$Start/Relay.hide()
	if await RoboLobbyManager.create_lobby_async(lobby_name, max_players, visibility_idx):
		_init_waiting_room()
	else:
		$Start/Relay.show()

func _init_waiting_room(auto_show: bool = true) -> void:
	if RoboLobbyManager.local_lobby == null:
		return
	
	$Start/WaitingRoom/List/VBox/Actions/Play.disabled = not RoboLobbyManager.local_lobby.is_owner()
	
	var lobby_name_attribute: Dictionary = RoboLobbyManager.local_lobby.get_attribute("LOBBYNAME")
	var lobby_name: String = lobby_name_attribute.value if (lobby_name_attribute != null and not lobby_name_attribute.is_empty()) else RoboLobbyManager.local_lobby.lobby_id
	$Start/WaitingRoom/Split/Host/VBox/Settings/Name.text = lobby_name
	var join_code_attribute: Dictionary = RoboLobbyManager.local_lobby.get_attribute("JOINCODE")
	var join_code: String = join_code_attribute.value if (join_code_attribute != null and not join_code_attribute.is_empty()) else "******"
	$Start/WaitingRoom/Split/Host/VBox/Settings/JoinCode.text = join_code
	$Start/WaitingRoom/Split/Host/VBox/Settings/MaxPlayers.value = RoboLobbyManager.local_lobby.max_members
	$Start/WaitingRoom/Split/Host/VBox/Settings/Visibility.select(RoboLobbyManager.local_lobby.permission_level)
	
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
	
	if auto_show:
		$Start/WaitingRoom.show()

func _update_waiting_room_players() -> void:
	if RoboLobbyManager.local_lobby == null or RoboLobbyManager.local_lobby.members == null:
		$Start/WaitingRoom/List/VBox/Actions/Kick.disabled = true
		return
	
	# Populate item list
	var item_list: ItemList = $Start/WaitingRoom/List/VBox/ItemList
	item_list.clear()
	for cur_player: HLobbyMember in RoboLobbyManager.local_lobby.members:
		var username_attribute: Dictionary = cur_player.get_attribute("USERNAME")
		var username: String = username_attribute.value if (username_attribute != null and not username_attribute.is_empty()) else "Player" + cur_player.product_user_id
		if cur_player.is_owner():
			username += " [Host]"
		elif cur_player.is_self():
			username += " [Self]"
		item_list.add_item(username)
	
	$Start/WaitingRoom/List/VBox/Actions/Kick.disabled = item_list.item_count < 2 or not RoboLobbyManager.local_lobby.is_owner()

func _on_peer_connection_established(_callback_data: Dictionary) -> void:
	print("Connection established")
	_update_waiting_room_players()

func _on_peer_connection_closed(_callback_data: Dictionary) -> void:
	print("Connection closed")
	_update_waiting_room_players()

func _on_lobby_updated() -> void:
	print_verbose("Lobby updated")
	_update_waiting_room_players()

func _on_kicked_from_lobby() -> void:
	print("Kicked from lobby")
	$Start/WaitingRoom.hide()
	$Start/Relay.show()

func _on_lobby_player_color_picker_created() -> void:
	_on_player_color_picker_created(_lobby_player_color_picker_button)

## Kick the selected player(s)
func _on_lobby_kick_pressed() -> void:
	if (RoboLobbyManager.local_lobby == null or
		not RoboLobbyManager.local_lobby.is_owner() or
		RoboLobbyManager.local_lobby.members == null):
		return
	
	var item_list: ItemList = $Start/WaitingRoom/List/VBox/ItemList
	if not item_list.is_anything_selected():
		return
	
	var selected_items: PackedInt32Array = item_list.get_selected_items()
	# Sort the array in descending order (so we kick members starting from the end of the array)
	selected_items.sort()
	selected_items.reverse()
	for i in selected_items:
		var member: HLobbyMember = null
		if i < RoboLobbyManager.local_lobby.members.size():
			member = RoboLobbyManager.local_lobby.members[i]
		
		if member == null or member.is_owner():
			continue
		
		await member.kick_member_async()

func _on_game_started(_level_idx: int) -> void:
	hide()

func _on_lobby_play_pressed() -> void:
	RoboLobbyManager.start_game()

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
