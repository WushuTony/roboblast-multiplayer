extends RigidBody3D
class_name Grenade

const EXPLOSION_SCENE := preload("explosion_visuals/explosion_scene.tscn")

## After this many bounces, the next collision will explode the grenade immediately[br]
## A negative value means no limit, zero means any collision will trigger the explosion
@export var max_bounces: int = 3
## If the grenade should bounce on enemies
@export var bounce_on_enemies: bool = false
## If the grenade should bounce on players
@export var bounce_on_players: bool = false
## If the grenade should bounce on misc damageables like boxes
@export var bounce_on_other_damageables: bool = true
## Always explode after that delay (to prevent a grenade never triggering)
@export var explode_after_delay: float = 2.5
## Forward impulse after an explosion inflicts damage.
@export var damage_impulse: float = 30.0
## Override the upward force of the damage impulse.
@export var upward_impulse: float = 5.0

var shooter: Node = null
var friendly_fire: bool = false
var damage_self: bool = false

# Custom gravity value that matches the trajectory predicted by the grenade launcher
var gravity: float = 0.0

var _bounces: int = 0
var _thrown_timer: float = 0.0
var _velocity: Vector3 = Vector3.ZERO

@onready var _collision_shape: CollisionShape3D = $CollisionShape3d
@onready var _explosion_area: Area3D = $ExplosionArea
@onready var _explosion_sound: AudioStreamPlayer3D = $ExplosionSound
@onready var _explosion_start_timer: Timer = $ExplosionStartTimer
@onready var _grenade_visuals: Node3D = $grenade


func _ready() -> void:
	if is_multiplayer_authority():
		_explosion_start_timer.timeout.connect(_explode)
	else:
		set_physics_process(false)

	if is_zero_approx(gravity):
		gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _physics_process(delta) -> void:
	if not is_multiplayer_authority():
		return

	var explode_immediately: bool = false
	_thrown_timer += delta
	if _thrown_timer >= explode_after_delay:
		explode_immediately = true

	_velocity += Vector3.DOWN * gravity * delta
	var collision: KinematicCollision3D = move_and_collide(_velocity * delta)
	if collision != null and not explode_immediately:
		var bounce: bool = _bounces < max_bounces
		if bounce:
			var collider: Object = collision.get_collider()
			if collider != null and collider.is_in_group("damageables"):
				if not bounce_on_enemies and collider.is_in_group("enemies"):
					bounce = false
				elif not bounce_on_players and collider.is_in_group("players"):
					bounce = false
				elif not bounce_on_other_damageables:
					bounce = false

		if bounce:
			_velocity = _velocity.bounce(collision.get_normal(0)) * 0.7
			_bounces += 1
			if _explosion_start_timer.is_stopped():
				_explosion_start_timer.start()
		else:
			# We hit a collision and cannot bounce, so explode immediately
			explode_immediately = true

	if explode_immediately:
		if not _explosion_start_timer.is_stopped():
			_explosion_start_timer.stop()
		_explode()


func _explode() -> void:
	if not is_multiplayer_authority():
		return

	var bodies: = _explosion_area.get_overlapping_bodies()
	for body in bodies:
		if not damage_self and body == shooter:
			continue

		var is_damageable: bool = body.is_in_group("damageables")
		var can_damage: bool = is_damageable
		if is_damageable:
			if not friendly_fire and shooter != null:
				if body.is_in_group("players"):
					can_damage = !shooter.is_in_group("players")
				elif body.is_in_group("enemies"):
					can_damage = !shooter.is_in_group("enemies")

		# Add some variance to the impact point
		var impact_point: Vector3 = (global_position - body.global_position).normalized()
		impact_point = (impact_point + Vector3.DOWN).normalized() * 0.5
		var force: Vector3 = -impact_point.normalized() * damage_impulse
		force.y = upward_impulse

		if is_damageable:
			var damage_data: Variant = {
				"impact_point": impact_point,
				"force": force,
				"can_damage": can_damage
			}
			if body.is_multiplayer_authority():
				body.damage(damage_data)
			else:
				_apply_damage.rpc_id(body.get_multiplayer_authority(), body.get_path(), damage_data)
		elif body is RigidBody3D:
			body.apply_impulse(force, impact_point)

	_play_explosion_effect.rpc()


@rpc("authority", "call_local", "reliable")
func _apply_damage(path: String, data: Variant) -> void:
	var target: Node = get_node(path)
	if target != null and target.is_multiplayer_authority():
		target.damage(data)


@rpc("authority", "call_local", "reliable")
func _play_explosion_effect() -> void:
	_grenade_visuals.hide()
	set_physics_process(false)
	_collision_shape.set_deferred("disabled", true)

	Level.play_sound(_explosion_sound, global_position, randfn(2.0, 0.1))

	var explosion: Node3D = EXPLOSION_SCENE.instantiate()
	explosion.transform.origin = position
	get_parent().add_child(explosion)

	if is_multiplayer_authority():
		await get_tree().create_timer(0.5).timeout
		queue_free()
