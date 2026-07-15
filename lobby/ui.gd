extends CanvasLayer

@onready var lobby: Lobby = get_parent()

func _ready():
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_server_disconnected():
	show()

# ENet

func _on_enet_join_pressed():
	var address: String = $Start/ENet/Join/VBox/Options/Address.text
	var port: int = $Start/ENet/Join/VBox/Options/Port.value
	lobby.start_enet_client(address, port)
	hide()

func _on_enet_host_pressed():
	var port: int = $Start/ENet/Host/VBox/Options/Port.value
	lobby.start_enet_server(port)
	hide()

# WebSocket

func _on_websocket_join_pressed():
	var url: String = $Start/WebSocket/Join/VBox/Options/Url.text
	lobby.start_websocket_client(url)
	hide()

func _on_websocket_host_pressed():
	var port: int = $Start/ENet/Host/VBox/Options/Port.value
	lobby.start_websocket_server(port)
	hide()
