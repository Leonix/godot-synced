extends Area2D

const MOTION_SPEED = 150

export var left = false

var _motion = 0
var _you_hidden = false

# 0 means local player
# this is changed from pong.gd
var belongs_to_peer_id = 0

# Drop-in replacement for Input that transparently transfers keypresses over the network
var sync_input = null

onready var _screen_size_y = get_viewport_rect().size.y

func _process(delta):
	
	if not sync_input or (sync_input.get_peer_id() and sync_input.get_peer_id() != belongs_to_peer_id):
		sync_input = SyncManager.get_input_facade(belongs_to_peer_id)

	_motion = sync_input.get_action_strength("move_down") - sync_input.get_action_strength("move_up")
	_motion *= MOTION_SPEED

	# Hide label instantly for another person's paddle, or after a move for your paddle.
	if not _you_hidden:
		if _motion != 0 or belongs_to_peer_id != 0:
			_hide_you_label()

	# In real life there will be no check for is_network_master()
	# 1) Write to position will be ignored on Client (unless CSP of cource)
	#    becase position will be inside SyncBase property
	# 2) Server-to-client sync will be done by SyncBase
	if is_network_master():
		translate(Vector2(0, _motion * delta))
		position.y = clamp(position.y, 16, _screen_size_y - 16)

		rpc_unreliable("set_pos_and_motion", position, _motion)

# Synchronize position and speed to the other peers.
puppet func set_pos_and_motion(pos, motion):
	position = pos
	_motion = motion

func _hide_you_label():
	_you_hidden = true
	get_node("You").hide()


func _on_paddle_area_enter(area):
	if is_network_master():
		# Random for new direction generated on each peer.
		area.rpc("bounce", left, randf())
