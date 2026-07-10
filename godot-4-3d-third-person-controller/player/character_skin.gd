class_name CharacterSkin
extends Node3D

## Emitted in animations like running when the character's feet hit the ground.
signal stepped

@export var main_animation_player : AnimationPlayer

var moving_blend_path := "parameters/StateMachine/move/blend_position"

# False : set animation to "idle"
# True : set animation to "move"
var moving : bool = false : set = set_moving

# Blend value between the walk and run cycle
# 0.0 walk - 1.0 run
@onready var move_speed : float = 0.0 : set = set_moving_speed
@onready var animation_tree : AnimationTree = $AnimationTree
@onready var state_machine : AnimationNodeStateMachinePlayback = animation_tree.get("parameters/StateMachine/playback")

var state: StringName = "idle":
	set(value): if state_machine != null: state_machine.travel(value)
	get(): return state_machine.get_current_node()


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1
	set_moving(false)


func set_moving(value : bool):
	moving = value
	if moving:
		state = "move"
	else:
		state = "idle"


func set_moving_speed(value : float):
	move_speed = clamp(value, 0.0, 1.0)
	animation_tree.set(moving_blend_path, move_speed)


func jump():
	state = "jump"


func fall():
	moving = false
	state = "fall"


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func _step() -> void:
	stepped.emit()


func set_color(color : Color):
	color.a = 0.01
	$gdbot/Armature/Skeleton3D/gdbot_mesh.get_surface_override_material(1).set("shader_parameter/screen_color", color)
	$gdbot/Armature/Skeleton3D/gdbot_mesh.get_surface_override_material(2).set("emission", color)
