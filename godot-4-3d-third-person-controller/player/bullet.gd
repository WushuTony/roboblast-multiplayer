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
	_projectile_sound.pitch_scale = randfn(1.0, 0.1)
	_projectile_sound.play()


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		global_position += velocity * delta
	
	_time_alive += delta
	
	_bullet_visuals.scale = Vector3.ONE * scale_decay.sample(_time_alive/_alive_limit)
	
	if _time_alive > _alive_limit:
		_destroy_bullet()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	# TODO: Check that the shooter is still alive
	if body.is_multiplayer_authority() and body.is_in_group("damageables"):
		var can_damage: bool = true
		if not friendly_fire and shooter != null:
			if body.is_in_group("players"):
				can_damage = !shooter.is_in_group("players")
			elif body.is_in_group("enemies"):
				can_damage = !shooter.is_in_group("enemies")
		if can_damage:
			var impact_point := global_position - body.global_position
			body.damage(impact_point, velocity)
	_destroy_bullet()


func _destroy_bullet():
	_bullet_visuals.hide()
	_projectile_sound.stop()
	
	set_process(false)
	_collision_shape.set_deferred("disabled", true)
	
	if is_multiplayer_authority():
		await get_tree().create_timer(0.5).timeout
		queue_free()
