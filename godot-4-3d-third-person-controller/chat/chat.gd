extends PanelContainer
class_name RoboChat

## If the chat should be enabled by default or not[br]
## When disabled, the chat needs to be enabled externally (e.g. by a lobby or a player)
@export var enabled_by_default: bool = false
## Focus the chat when the "focus_chat" input is pressed
@export var grab_focus_on_press: bool = false
## Unfocus the chat when the "pause" input is pressed
@export var unfocus_on_pause: bool = false
## Unfocus the chat when the player left clicks outside the chat
@export var unfocus_on_click: bool = false
## Color used by modulate when the chat is focused
@export var focused_color: Color = Color.WHITE
## Color used by modulate when the chat is not focused
@export var unfocused_color: Color = Color(1.0, 1.0, 1.0, 0.75)
## When testing if a position is within the chat panel area, expand the test area
@export var expand_has_position: Vector2 = Vector2(8.0, 8.0)

@onready var _title: Label = $VBox/Title
@onready var _item_list: AutowrapItemList = $VBox/ItemList
@onready var _line_edit: LineEdit = $VBox/Text

var is_chat_enabled: bool = false
var is_chatting: bool = false
var prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

## Enable the text chat
func enable() -> void:
	var should_process_inputs: bool = grab_focus_on_press or unfocus_on_pause or unfocus_on_click
	set_process_input(should_process_inputs)
	set_process_shortcut_input(should_process_inputs)
	show()
	is_chat_enabled = true

	if not _line_edit.text_submitted.is_connected(_on_chat_message_submitted):
		_line_edit.text_submitted.connect(_on_chat_message_submitted)
	if not RoboLobbyManager.chat_message_received.is_connected(_on_chat_message_received):
		RoboLobbyManager.chat_message_received.connect(_on_chat_message_received)

## Disable the text chat
func disable() -> void:
	set_process_input(false)
	set_process_shortcut_input(false)
	hide()
	is_chat_enabled = false

	if _line_edit.text_submitted.is_connected(_on_chat_message_submitted):
		_line_edit.text_submitted.disconnect(_on_chat_message_submitted)
	if RoboLobbyManager.chat_message_received.is_connected(_on_chat_message_received):
		RoboLobbyManager.chat_message_received.disconnect(_on_chat_message_received)

func _ready() -> void:
	if grab_focus_on_press:
		var has_joypads: bool = Input.get_connected_joypads().size() > 0
		var event_list = InputMap.action_get_events("focus_chat")
		var input_to_press: String = ""
		for event in event_list:
			if has_joypads:
				if event is InputEventJoypadButton:
					input_to_press = _get_joypad_button_name(event)
			else:
				if event is InputEventKey:
					input_to_press = OS.get_keycode_string(event.key_label)
		_line_edit.placeholder_text = "Press [" + input_to_press + "] to focus chat"
		_set_focus_modulate(unfocused_color)

	if enabled_by_default:
		enable()
	else:
		disable()

func _input(event: InputEvent) -> void:
	if not is_chat_enabled or not get_window().has_focus():
		return

	if not event.is_echo():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			if unfocus_on_pause and is_chatting:
				accept_event()
				unfocus_chat()
				return
		if event.is_action_pressed("focus_chat"):
			if grab_focus_on_press and not is_chatting:
				accept_event()
				focus_chat()
				return

	if is_chatting and event is InputEventMouseButton:
		accept_event()
		if unfocus_on_click and\
			event.is_pressed() and\
			event.button_index == MouseButton.MOUSE_BUTTON_LEFT and\
			not _has_point(event.position):
			unfocus_chat()

func _shortcut_input(event: InputEvent) -> void:
	if not is_chat_enabled or not get_window().has_focus():
		return

	if is_chatting:
		if event is not InputEventMouse:
			accept_event()

func _has_point(point: Vector2) -> bool:
	var rect: Rect2 = get_rect()
	if not expand_has_position.is_zero_approx():
		rect.position -= expand_has_position
		rect.size += (expand_has_position * 2)
	return rect.has_point(point)

## Clear all the chat messages
func clear() -> void:
	if _item_list != null:
		_item_list.clear()

func focus_chat() -> void:
	if is_chatting:
		return
	prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_focus_modulate(focused_color)
	_line_edit.grab_focus()
	is_chatting = true

func unfocus_chat() -> void:
	if not is_chatting:
		return
	_set_focus_modulate(unfocused_color)
	_line_edit.clear()
	_line_edit.release_focus()
	Input.mouse_mode = prev_mouse_mode
	is_chatting = false

func _set_focus_modulate(new_color: Color):
	_title.self_modulate = new_color
	_item_list.self_modulate = new_color

func _on_chat_message_submitted(new_text: String) -> void:
	if RoboLobbyManager.send_chat_message(new_text):
		_line_edit.clear()
	else:
		# Temporarily disable the text box and shake to indicate the failure
		_line_edit.editable = false
		var tween: Tween = create_tween()
		var original_text_position: Vector2 = _line_edit.position
		const shake_duration: float = 0.3
		tween.tween_method(_line_edit_shake.bind(original_text_position), 1.0, 0.0, shake_duration)\
			.set_trans(Tween.TRANS_LINEAR)\
			.set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(_on_line_edit_shake_finished.bind(original_text_position))

func _line_edit_shake(decay: float, original_text_position: Vector2) -> void:
	if _line_edit == null:
		return

	# Calculate a random offset scaled by the current decay phase
	const shake_intensity: float = 10.0
	var current_intensity: float = shake_intensity * decay
	var random_offset: Vector2 = Vector2(
		randf_range(-current_intensity, current_intensity),
		randf_range(-current_intensity, current_intensity)
	)

	_line_edit.position = original_text_position + random_offset

func _on_line_edit_shake_finished(original_text_position: Vector2) -> void:
	if _line_edit != null:
		_line_edit.position = original_text_position
		_line_edit.editable = true

func _on_chat_message_received(username: String, message: String) -> void:
	if _item_list != null:
		var item_indexes: Array[int] = _item_list.add_wrapped_items(username + ": " + message, null, false)
		for idx in item_indexes:
			_item_list.set_item_tooltip_enabled(idx, false)

static func _get_joypad_button_name(event: InputEventJoypadButton) -> String:
	match event.button_index:
		7:
			return "L3"
		8:
			return "R3"
		_:
			return ""
