# Environment variable loader autoload
extends Node

var _env = {}

func load_env(p_path := "res://.env"):
	if not FileAccess.file_exists(p_path):
		return {}

	var file = FileAccess.open(p_path, FileAccess.READ)
	var ret = {}
	while not file.eof_reached():
		var line = file.get_line()
		# skip comment lines
		if line.lstrip(" ").begins_with("#"): continue
		var tokens = line.split("=", false, 1)
		if tokens.size() == 2:
			ret[tokens[0]] = tokens[1].lstrip("\"").rstrip("\"");
	return ret

func _ready() -> void:
	_env = load_env()

func get_var(p_name: String):
	if _env.has(p_name):
		return _env[p_name]
	return null

# Example .env file format:
# PRODUCT_NAME="My Game"
# PRODUCT_VERSION="1.0.0"
# PRODUCT_ID="your_product_id"
# SANDBOX_ID="your_sandbox_id"
# DEPLOYMENT_ID="your_deployment_id"
# CLIENT_ID="your_client_id"
# CLIENT_SECRET="your_client_secret"
# ENCRYPTION_KEY="64_character_random_string"
