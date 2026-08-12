extends Area3D
class_name MeleeAttackArea

## Forward impulse after an attack inflicts damage.
@export var damage_impulse: float = 10.0
## Override the upward force of the damage impulse.
@export var upward_impulse: float = 0.5
## If [code]true[/code], repulse away from the collision.[br]
## Otherwise, the impulse follows the attacker's facing direction.
@export var repulse_from_collision: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3d

var attacker: Node = null
var friendly_fire: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


func activate():
	collision_shape.set_deferred("disabled", false)


func deactivate():
	collision_shape.set_deferred("disabled", true)


func _on_body_entered(body: Node3D) -> void:
	if body == attacker:
		return

	if body.is_multiplayer_authority() and body.is_in_group("damageables"):
		var can_damage: bool = true
		if not friendly_fire and attacker != null:
			if body.is_in_group("players"):
				can_damage = !attacker.is_in_group("players")
			elif body.is_in_group("enemies"):
				can_damage = !attacker.is_in_group("enemies")

		var impact_point: Vector3 = global_position - body.global_position
		if not repulse_from_collision:
			if attacker is Player:
				impact_point = attacker._rotation_root.transform.basis * Vector3.FORWARD
			else:
				impact_point = attacker.transform.basis * Vector3.FORWARD
		var force: Vector3 = -impact_point.normalized() * damage_impulse
		force.y = upward_impulse

		var damage_data: Variant = {
			"impact_point": impact_point,
			"force": force,
			"can_damage": can_damage
		}
		body.damage(damage_data)
