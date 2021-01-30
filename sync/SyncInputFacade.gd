extends Node
class_name SyncInputFacade

# Pretends to be like Godot's Input class, serving as a (limited) drop-in replacement.
# When attached to local SyncPeer, uses last locally sampled input frame.
# When attached to remote SyncPeer, uses data previously received via network.
# (Remote SyncPeers only exist on Server.)

#signal _input # !!! TODO not implemented

func is_action_pressed(action: String)->bool:
	var result = _get_value(action)
	if not result:
		return false
	return result > 0

func is_action_just_pressed(action: String)->bool:
	var value = _get_value(action)
	if not value or value == 0.0:
		return false
	return _get_value(action, -2) == 0.0

func is_action_just_released(action: String)->bool:
	var value = _get_value(action)
	if not value or value != 0.0:
		return false
	return _get_value(action, -2) != 0.0

func get_action_strength(action: String)->float:
	var result = _get_value(action)
	if not result:
		return 0.0
	return result

func _get_value(action, input_id=-1):
	var peer = get_parent()
	if not peer:
		return null
	# If last input from this client was too long ago, return empty frame.
	# This stops extrapolating last known frame after certain number of steps.
	if peer.input_id - peer.storage.last_input_id > SyncManager.input_prediction_max_frames:
		return null
	if input_id < 0:
		input_id = peer.input_id + 1 + input_id
	var frame = peer.storage.read(input_id)
	if not (action in frame):
		return null
	return frame[action]
	
func get_peer_id():
	var peer = get_parent()
	if not peer:
		return null
	return int(peer.name)
	
func action_press(_action: String)->void:
	assert(false, 'SyncInputFacade->action_press() is not implemented')
	
func action_release(_action: String)->void:
	assert(false, 'SyncInputFacade->action_release() is not implemented')

# Fake SyncInputFacade to return when asked for unknown peer_unique_id
class FakeInputFacade:
	signal _input
	func get_peer_id():
		return null
	func is_action_pressed(_action: String)->bool:
		return false
	func is_action_just_pressed(_action: String)->bool:
		return false
	func is_action_just_released(_action: String)->bool:
		return false
	func get_action_strength(_action: String)->float:
		return 0.0
	func action_press(_action: String)->void:
		pass
	func action_release(_action: String)->void:
		pass
	func __z():
		emit_signal("_input")
