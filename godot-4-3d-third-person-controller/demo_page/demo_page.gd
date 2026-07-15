extends Node

enum INSTRUCTION_TYPES {KEYBOARD, JOYPAD}

@onready var demo_page_root: Control = %DemoPageRoot
@onready var resume_button: Button = %ResumeButton
@onready var exit_button: Button = %ExitButton
@onready var keyboard_button: Button = %KeyboardButton
@onready var joypad_button: Button = %JoypadButton
@onready var grid_container_keyboard: GridContainer = %GridContainerKeyboard
@onready var grid_container_joypad: GridContainer = %GridContainerJoypad

var can_pause_game: bool = true
var headless_mode: bool = (DisplayServer.get_name() == "headless")
var players_pausing_game: Array[int] = []


func _ready() -> void:
	if can_pause_game:
		get_tree().paused = true
	
	if headless_mode:
		return
	
	request_pause_demo.rpc()
	
	resume_button.grab_focus.call_deferred()
	
	demo_page_root.gui_input.connect(_demo_page_root_gui_input)
	resume_button.pressed.connect(_on_resume_button_pressed)
	exit_button.pressed.connect(get_tree().quit)
	keyboard_button.pressed.connect(change_instruction.bind(INSTRUCTION_TYPES.KEYBOARD))
	joypad_button.pressed.connect(change_instruction.bind(INSTRUCTION_TYPES.JOYPAD))
	
	if Input.get_connected_joypads().size() > 0:
		change_instruction(INSTRUCTION_TYPES.JOYPAD)
	else:
		change_instruction(INSTRUCTION_TYPES.KEYBOARD)


func _demo_page_root_gui_input(_event: InputEvent) -> void:
	if demo_page_root.is_visible():
		demo_page_root.accept_event()


func _input(event: InputEvent) -> void:
	if not get_window().has_focus():
		return
	
	if event.is_action_pressed("pause") and not event.is_echo():
		demo_page_root.accept_event()
		if can_pause_game:
			if demo_page_root.is_visible():
				request_resume_demo.rpc()
			else:
				request_pause_demo.rpc()
		else:
			if demo_page_root.is_visible():
				hide_demo_page()
			else:
				show_demo_page()


func _shortcut_input(event: InputEvent) -> void:
	if demo_page_root.is_visible():
		if event is not InputEventMouse:
			demo_page_root.accept_event()


func change_instruction(type: int) -> void:
	match type:
		INSTRUCTION_TYPES.KEYBOARD:
			keyboard_button.modulate.a = 1.0
			joypad_button.modulate.a = 0.3
			grid_container_keyboard.show()
			grid_container_joypad.hide()
		INSTRUCTION_TYPES.JOYPAD:
			keyboard_button.modulate.a = 0.3
			joypad_button.modulate.a = 1.0
			grid_container_keyboard.hide()
			grid_container_joypad.show()


@rpc("any_peer", "call_local", "reliable")
func request_pause_demo() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id() if (multiplayer.get_remote_sender_id() != 0) else multiplayer.get_unique_id()
	if not players_pausing_game.has(peer_id):
		players_pausing_game.append(peer_id)
	pause_demo.rpc()


@rpc("authority", "call_local", "reliable")
func pause_demo() -> void:
	if can_pause_game:
		get_tree().paused = true
	show_demo_page()


func _on_resume_button_pressed() -> void:
	request_resume_demo.rpc()


@rpc("any_peer", "call_local", "reliable")
func request_resume_demo() -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id() if (multiplayer.get_remote_sender_id() != 0) else multiplayer.get_unique_id()
	players_pausing_game.erase(peer_id)
	if players_pausing_game.is_empty():
		resume_demo.rpc()


@rpc("authority", "call_local", "reliable")
func resume_demo() -> void:
	if multiplayer.is_server():
		players_pausing_game.clear()
	get_tree().paused = false
	# If the game has been unpaused once, only show/hide the demo page
	can_pause_game = false
	hide_demo_page()


func show_demo_page() -> void:
	if headless_mode:
		return
	demo_page_root.show()
	var tween := create_tween()
	tween.tween_property(demo_page_root, "modulate", Color.WHITE, 0.3)
	tween.tween_callback(resume_button.grab_focus)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_demo_page() -> void:
	if headless_mode:
		return
	var tween := create_tween()
	tween.tween_property(demo_page_root, "modulate", Color.TRANSPARENT, 0.3)
	tween.tween_callback(demo_page_root.hide)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
