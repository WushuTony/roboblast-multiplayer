extends Node3D

@onready var _client_synchronizer: MultiplayerSynchronizer = $ClientSynchronizer

var _bots: Array[Bot] = []
var _killed_bots: Array[StringName] = []


func _ready():
	for child in get_children():
		if child is Bot:
			if multiplayer.is_server():
				child.on_killed.connect(_on_server_bot_killed)
			_bots.append(child)

	if not multiplayer.is_server():
		# This callback makes sure any late joiner doesn't see bots that are already dead
		_client_synchronizer.delta_synchronized.connect(_on_delta_synchronized)


func _on_delta_synchronized():
	for bot in _bots:
		if _killed_bots.has(bot.name):
			print_verbose(bot.name, " was killed, removing it from the scene")
			bot.prepare_destroy(0.0)

	_client_synchronizer.delta_synchronized.disconnect(_on_delta_synchronized)


func _on_server_bot_killed(bot: Bot):
	_bots.erase(bot)
	_killed_bots.append(bot.name)
