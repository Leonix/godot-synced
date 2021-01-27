extends Node

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
	if not peer or not peer.storage.ready_to_read():
		return null
	var property = peer.storage
	
	# If last input from this client was too long ago, return empty frame
	if peer.last_input_id - property.last_state_id > SyncManager.input_prediction_max_frames:
		return null
	
	var frame = property.last(1-input_id) if input_id < 0  else property[input_id]
	if not (action in frame):
		return null
	return frame[action]
	
func action_press(action: String)->void:
	assert(false, 'SyncInputFacade->action_press() is not implemented')
	
func action_release(action: String)->void:
	assert(false, 'SyncInputFacade->action_release() is not implemented')
