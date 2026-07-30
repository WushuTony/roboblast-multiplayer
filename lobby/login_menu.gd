extends Control

@export var online_scene: PackedScene = preload("res://lobby/game_session_manager.tscn")
@export var offline_scene: PackedScene = preload("res://lobby/game_session_manager.tscn")

@onready var message_label: Label = %MessageDisplay
@onready var online_button: Button = %Online
@onready var offline_button: Button = %Offline
@onready var message_dots_timer: Timer = %MessageDotsTimer

func _ready() -> void:
	_initialise_lobby()

func _initialise_lobby():
	online_button.disabled = true
	if message_label.text.is_empty():
		message_label.text = "Initialising online services"
	
	if await RoboLobbyManager.initialise_async():
		message_label.text = "Online services initialised"
		online_button.disabled = false
	else:
		if message_label.text.begins_with("Initialising"):
			message_label.text = "Failed to initialise online services\nTrying again"
		await get_tree().create_timer(1.0).timeout
		_initialise_lobby.call_deferred()

func _on_message_dots_timer_timeout() -> void:
	if RoboLobbyManager.is_initialised():
		message_dots_timer.stop()
		return
	
	if message_label.text.ends_with("..."):
		message_label.text = message_label.text.left(-3)
	else:
		message_label.text += "."

func _on_online_pressed() -> void:
	_change_scene_to_packed(online_scene, "Failed to load the online scene")

func _on_offline_pressed() -> void:
	RoboLobbyManager.is_singleplayer = true
	if not _change_scene_to_packed(offline_scene, "Failed to load the offline scene"):
		RoboLobbyManager.is_singleplayer = false

func _change_scene_to_packed(packed_scene: PackedScene, error_message: String) -> bool:
	online_button.disabled = true
	offline_button.disabled = true
	var err: Error = get_tree().change_scene_to_packed(packed_scene)
	if err != OK:
		message_label.text = error_message
		online_button.disabled = false
		offline_button.disabled = false
	return err == OK
