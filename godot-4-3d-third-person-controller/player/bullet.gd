extends Node3D
class_name Bullet

@export var scale_decay: Curve

var distance_limit: float = 14.0
var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null
var friendly_fire: bool = false

@onready var _area: Area3D = $Area3d
@onready var _collision_shape: CollisionShape3D = $Area3d/CollisionShape3d
@onready var _bullet_visuals: Node3D = $Bullet
@onready var _projectile_sound: AudioStreamPlayer3D = $ProjectileSound

var _time_alive: float = 0.0
var _alive_limit: float = 0.0


func _ready() -> void:
	_area.body_entered.connect(_on_body_entered)
	look_at(global_position + velocity)
	_alive_limit = distance_limit / velocity.length()
	Level.play_sound(_projectile_sound, global_position, randfn(1.0, 0.1))


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		global_position += velocity * delta
	
	_time_alive += delta
	
	_bullet_visuals.scale = Vector3.ONE * scale_decay.sample(_time_alive/_alive_limit)
	
	if _time_alive > _alive_limit or\
		not is_instance_valid(shooter) or\
		(shooter.has_method("is_alive") and\
		not shooter.is_alive()):
		_destroy_bullet()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	if body.is_multiplayer_authority() and body.is_in_group("damageables"):
		var can_damage: bool = true
		if not friendly_fire and shooter != null:
			if body.is_in_group("players"):
				can_damage = !shooter.is_in_group("players")
			elif body.is_in_group("enemies"):
				can_damage = !shooter.is_in_group("enemies")
		var impact_point := global_position - body.global_position
		var damage_data: Variant = {
			"impact_point": impact_point,
			"force": velocity,
			"can_damage": can_damage
		}
		body.damage(damage_data)
	_destroy_bullet()


func _destroy_bullet():
	_bullet_visuals.hide()
	
	set_process(false)
	_collision_shape.set_deferred("disabled", true)
	
	if is_multiplayer_authority():
		await get_tree().create_timer(0.5).timeout
		queue_free()
