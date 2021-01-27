extends Node

class_name SyncInput

# Dictionary (peer_id => SyncProperty) stores a history of input frames from both
# local peer and remote peers. Local peer uses special peer_id=0 which is synonymous
# with get_tree().multiplayer.get_network_unique_id().
# Each input frame is a Dictionary mapping Input action name:String to value.
# On Client, storage contains no input from remote peers.
var storage = {}

# Dictionary (peer_id => SyncInputFacade) stores facades for both local 
# and remote players. Local peer uses special peer_id=0 which is synonymous
# with get_tree().multiplayer.get_network_unique_id().
# On client, remote facades never register any input.
# On server, they take previously received input frames from storage.
# Remote facades get dropped upon client disconnect. All objects that subscribed
# to signals from remote facades will no lonnger receive any input.
var facades = {}

func _ready():
	# We use a special peer_id=0 to designate local peer.
	# This saves hustle in case get_tree().multiplayer.get_network_unique_id() changes.
	facades[0] = SyncInputFacade.new(weakref(self), 0)
	storage[0] = SyncProperty.new({
		max_extrapolation = 0,
		missing_state_interpolation = SyncProperty.NO_INTERPOLATION,
		interpolation = SyncProperty.NO_INTERPOLATION,
		sync_strategy = SyncProperty.DO_NOT_SYNC
	})
	storage[0].resize(get_parent().input_frames_history_size)

func sample(state_id, input_id):
	pass # !!!

func send_batch():
	pass # !!!

# Returns an object suitable for use as a limited replacement of Godot's Input class.
# 0 or get_tree().multiplayer.get_network_unique_id() means local player.
func get_facade(peer_unique_id:int = 0)->SyncInputFacade:
	if get_tree().multiplayer and peer_unique_id == get_tree().multiplayer.get_network_unique_id():
		peer_unique_id = 0
	if peer_unique_id in facades:
		return facades[peer_unique_id]
	return SyncInputFacade.new(weakref(self), peer_unique_id)

# Update storage according to given network_peer_id list.
# Remove all peers that are not in the list and add peers that are in the list.
func update_peers(peer_ids:Array):
	var exists = {}
	for peer_id in peer_ids:
		exists[peer_id] = true
		if not (peer_id in storage):
			storage[peer_id] = SyncProperty.new({
				max_extrapolation = 0,
				missing_state_interpolation = SyncProperty.NO_INTERPOLATION,
				interpolation = SyncProperty.NO_INTERPOLATION,
				sync_strategy = SyncProperty.DO_NOT_SYNC
			})
			storage[peer_id].resize(get_parent().input_frames_history_size)

# Pretends to be like Godot's Input class, serving as a (limited) drop-in replacement.
# On client, uses last locally sampled input frame.
# On server, receives data via network from peers.
class SyncInputFacade:
	var peer_id: int
	var parent: WeakRef
	
	func _init(sync_input: WeakRef, peer_unique_id: int):
		peer_id = peer_unique_id
		parent = sync_input

	signal _input # !!!

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
		var si = parent.get_ref()
		if not si or not (peer_id in si.storage):
			return null
		var frame = si.storage[peer_id]
		if not (action in frame):
			return null
		if input_id < 0:
			return frame[action].last(1-input_id)
		return frame[action][input_id]
		
	func action_press(action: String)->void:
		assert(false, 'SyncInput->action_press() is not implemented')
		
	func action_release(action: String)->void:
		assert(false, 'SyncInput->action_release() is not implemented')
