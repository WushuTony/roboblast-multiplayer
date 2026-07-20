extends Area3D

## Coins lost when a player hit the death plane
@export var player_coins_count: int = 5
## Spawn the lost coins by the player[br]
## [b]Note:[/b] They will likely be destroyed by the death plane
@export var spawn_player_coins: bool = false


func _init() -> void:
	monitorable = false
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, true) # Dynamic Objects
	set_collision_mask_value(2, false) # Static Objects
	set_collision_mask_value(3, true) # Coins
	set_collision_mask_value(4, true) # Players
	set_collision_mask_value(5, true) # Bots
	set_collision_mask_value(6, true) # Pushable Objects


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_multiplayer_authority():
		return

	if body is Player:
		body.lose_coins(player_coins_count, spawn_player_coins)
		body.reset_position()
	else:
		print(body.name, " has hit the death plane and is being destroyed")
		body.queue_free.call_deferred()
