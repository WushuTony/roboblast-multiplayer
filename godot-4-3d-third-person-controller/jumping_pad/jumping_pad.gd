extends Area3D

@export var impulse_strength := 10.0
@onready var mushroom: Node3D = %mushroom


func _ready() -> void:
	body_entered.connect(
		func(body: Node3D) -> void:
			if body is Player:
				body.is_using_jumping_pad = true
				body.velocity.y = body.jump_initial_impulse + impulse_strength

				var tween := create_tween()
				mushroom.scale.y = 0.4
				tween.tween_property(mushroom, "scale:y", 1.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	)
