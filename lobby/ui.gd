extends CanvasLayer

@onready var lobby: Lobby = get_parent()
@onready var _enet_address_line_edit: LineEdit = $Start/ENet/Panel/VBox/Options/Address
@onready var _enet_port_spin_box: SpinBox = $Start/ENet/Panel/VBox/Options/Port
@onready var _enet_player_name_line_edit: LineEdit = $Start/ENet/Custom/VBox/Options/Name
@onready var _enet_player_color_picker_button: ColorPickerButton = $Start/ENet/Custom/VBox/Options/ColorPicker

func _ready():
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_enet_player_name_line_edit.text_changed.connect(_on_player_name_changed)
	_enet_player_color_picker_button.color_changed.connect(_on_player_color_changed)
	_enet_player_color_picker_button.picker_created.connect(_on_player_color_picker_created)
	_enet_player_color_picker_button.popup_closed.connect(_on_player_color_picker_closed)

func _on_server_disconnected():
	show()

# ENet

func _on_enet_join_pressed():
	var address: String = _enet_address_line_edit.text
	var port: int = int(_enet_port_spin_box.value)
	lobby.start_enet_client(address, port)
	hide()

func _on_enet_host_pressed():
	var port: int = int(_enet_port_spin_box.value)
	lobby.start_enet_server(port)
	hide()

# WebSocket

func _on_websocket_join_pressed():
	var url: String = $Start/WebSocket/Join/VBox/Options/Url.text
	lobby.start_websocket_client(url)
	hide()

func _on_websocket_host_pressed():
	var port: int = $Start/WebSocket/Host/VBox/Options/Port.value
	lobby.start_websocket_server(port)
	hide()

# Player Customisation

func _on_player_name_changed(new_name: String):
	lobby.local_player_name = new_name

func _on_player_color_changed(new_color: Color):
	lobby.local_player_color = new_color

func _on_player_color_picker_created():
	_enet_player_color_picker_button.get_popup().about_to_popup.connect(_on_player_color_picker_opened)
	_on_player_color_picker_opened()
	_enet_player_color_picker_button.picker_created.disconnect(_on_player_color_picker_created)

func _on_player_color_picker_opened():
	hide()

func _on_player_color_picker_closed():
	show()
