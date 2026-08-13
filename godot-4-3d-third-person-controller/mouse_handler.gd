extends Node

var _cur_mouse_context: int = -1
var _mouse_contexts: Dictionary[int, Variant] = {}

## Request to change the mouse mode in the [param p_owner]'s context.[br][br]
## The [param p_owner] to track who made the request and later clear it up when [method release_mouse_mode] is called.[br]
## The [param new_mouse_mode] we want to use in the [param p_owner]'s context.[br]
## A [i]lower[/i] [param priority] value will override the other mouse modes.
func request_mouse_mode(p_owner: Object, new_mouse_mode: Input.MouseMode, priority: int) -> void:
	if not p_owner:
		push_error("New mouse mode requested with an invalid owner")
		return

	var new_context: int = p_owner.get_instance_id()
	_mouse_contexts[new_context] = {
		"mouse_mode": new_mouse_mode,
		"priority": priority
	}
	if _cur_mouse_context == -1 or\
	priority < _mouse_contexts[_cur_mouse_context].priority:
		_cur_mouse_context = new_context
		Input.mouse_mode = new_mouse_mode

## Release the mouse mode held by the [param p_owner]'s context.[br][br]
## If that mode is the current one, then another one is picked based on the lowest priority.
func release_mouse_mode(p_owner: Object) -> void:
	if not p_owner:
		push_error("Cannot release mouse mode with an invalid owner")
		return

	var owner_id: int = p_owner.get_instance_id()
	if not _mouse_contexts.erase(owner_id):
		push_warning("Failed to release %s from the mouse contexts" % p_owner.name)
		return

	# If we just released the current context, we need to find a new one based on the lowest priority.
	if _cur_mouse_context == owner_id:
		if _mouse_contexts.is_empty():
			push_warning("Released %s from the mouse contexts, but there is no mouse context remaining to fall back into" % p_owner.name)
			_cur_mouse_context = -1
			return
		var new_context: int = -1
		var lowest_priority: int = 0
		for context in _mouse_contexts:
			if new_context == -1 or\
			_mouse_contexts[context].priority < lowest_priority:
				new_context = context
				lowest_priority = _mouse_contexts[context].priority
		if new_context != -1:
			_cur_mouse_context = new_context
			Input.mouse_mode = _mouse_contexts[new_context].mouse_mode
		else:
			push_warning("Released %s from the mouse contexts, but the new context is invalid" % p_owner.name)
			_cur_mouse_context = -1
