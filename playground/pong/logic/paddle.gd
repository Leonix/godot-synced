extends Area2D

const MOTION_SPEED = 150

export var left = false

var _motion = 0
var _you_hidden = false

onready var _screen_size_y = get_viewport_rect().size.y
onready var synced = $Sync

func _process(_delta):
	# Hide label instantly for another person's paddle, or after a move for your paddle.
	if not _you_hidden:
		if _motion != 0 or not synced.is_local_peer():
			_hide_you_label()

func _physics_process(delta):
	_motion = synced.input.get_action_strength("move_down") - synced.input.get_action_strength("move_up")
	_motion *= MOTION_SPEED

	translate(Vector2(0, _motion * delta))
	position.y = clamp(position.y, 16, _screen_size_y - 16)

func _hide_you_label():
	_you_hidden = true
	get_node("You").hide()

func _on_paddle_area_enter(area):
	# Random for new direction generated on each peer.
	area.bounce(left, randf())
