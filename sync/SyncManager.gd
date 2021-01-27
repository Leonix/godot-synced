extends Node

#
# Sync lib requires this class to be autoloaded as SyncManager singleton.
#
# Does the RPC to send Input frames (keyboard and mouse sampling status)
# from Client to Server. Stores data in child nodes, see SyncPeer.tscn scene.
# Local player has a special SyncPeer id=0 attached at all times, including
# even when no networking is enabled.
#

#
# Configuration constants
#

# How long (in state_ids) should history be for each interpolated property on a client.
# Client stores history of all interpolated properties in order to render game world
# slightly in the past. This should tolerage one network packet drop.
# I.e. if sampling 60 state_ids per second, network send to each client is
# 30 times a second, means packet drop loses 2 state_ids, therefore 
# this should be at least 4. 5 looks like a decent default.
# Changing this will only affect newly created SyncBases. 
# Only change before scene is loaded.
var client_interpolated_property_history_size = 5

# How long (in state_ids) should history be for each property on a server.
# This determines max lag-compensation span and max time depth.
# Changing this will only affect newly created SyncBases. 
# Only change before scene is loaded.
var server_property_history_size = 60

# How many times per second to send batches of input frames from client on server.
# Client samples input every _physics_process() (that is, at a rate of Engine.iterations_per_second)
# and buffers sampled frames. Client sends batches to Server at this rate.
var input_sendrate = 30

# Batch size when sending input frames. This number of frames is sent at input_sendrate.
# In case input_frames_min_batch * input_sendrate exceeds Engine.iterations_per_second
# it adds redundancy, improving tolerance to packet loss, at the cost of increased traffic.
var input_frames_min_batch = 3

# Server: max number of frames to pool for later processing.
# input_frames_history_size * input_sendrate should exceed Engine.iterations_per_second
# input_frames_history_size must exceed input_frames_min_batch
var input_frames_history_size = 5

# Server: when no input frames are ready from peer at the moment of consumption,
# server is allowed to copy last valid frame this many times.
# Reasonable value allows to tolerate 1-2 input packets go missing.
var input_prediction_max_frames = 4

# Last input frame that has been captured and either sent to server (if on client)
# or processed locally (if on server)
var input_id = 1 setget set_input_id, get_input_id

# Last World State id that has been captured.
var state_id = 1 setget set_state_id, get_state_id

# Last World State id that has been captured.
var state_id_frac setget , get_state_id_frac

# We want first call to _process() after _physics_process() 
# to see integer state_id_frac. But we don't want to interfere
# too much with regularity of state_id_frac. The greater this setting is,
# the stronger we try to make first state_id_frac into integer,
# at the cost of possible large jumps in state_id_frac value
# visible inside _process().
# 1 will force state_id_frac to be integer first time after _physics_process().
# 0 will disable trying to change state_id_frac.
var state_id_frac_to_integer_reduction = 0.04

#
# Private vars zone
#

# Shenanigans needed to calculate state_id_frac
var state_id_frac_fix = 0.0
var first_process_since_physics_process = true

# Used to control rate of sending input from client to server
var _mtime_last_input_batch_sent = 0.0

var SyncPeer = preload("res://sync/SyncPeer.tscn")

func _ready():
	var local_peer = SyncPeer.instance()
	local_peer.name = '0'
	self.add_child(local_peer)

func _process(_delta):
	
	if first_process_since_physics_process and state_id_frac_to_integer_reduction > 0:
		state_id_frac_fix = move_toward(state_id_frac_fix, Engine.get_physics_interpolation_fraction(), state_id_frac_to_integer_reduction)
		first_process_since_physics_process = false

func is_server():
	return get_tree().network_peer and get_tree().is_network_server()

func is_client():
	return get_tree().network_peer and not get_tree().is_network_server()

func _physics_process(_delta):

	# Server: send previous World State to clients
	if is_server():
		pass # !!!
	
	# Increment global state time
	first_process_since_physics_process = true
	input_id += 1
	state_id += 1
	
	# Build new Input frame
	sample_input()

	# Server: update Client-owned properties of all SyncBase objects, 
	# taking them from new input frame from each client
	if is_server():
		pass # !!!
	
	# Client: send input frames to server if time has come
	if is_client():
		var time = OS.get_system_time_msecs()
		if (time - _mtime_last_input_batch_sent) * input_sendrate >= 1.0:
			_mtime_last_input_batch_sent = time
			send_input_batch()

# Game code calls this
# - on server for each client connected, providing peer_id;
# - on client when connected to server, with no peer_id
func client_connected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = SyncPeer.instance()
		peer.name = str(peer_id)
		self.add_child(peer)

# Game code calls this 
# - on server when existing client disconnects, providing peer_id;
# - on client when disconnected from server, with no peer_id
func client_disconnected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = get_node(str(peer_id))
		if peer:
			peer.queue_free()

# Update storage according to given network_peer_id list.
# Remove all peers that are not in the list and add peers that are in the list.
func update_peers(peer_ids:Array):
	var exists = {}
#!!!for peer_id in peer_ids:
#		exists[peer_id] = true
#		if not (peer_id in storage):
#			storage[peer_id] = SyncProperty.new({
#				max_extrapolation = 0,
#				missing_state_interpolation = SyncProperty.NO_INTERPOLATION,
#				interpolation = SyncProperty.NO_INTERPOLATION,
#				sync_strategy = SyncProperty.DO_NOT_SYNC
#			})
#			storage[peer_id].resize(get_parent().input_frames_history_size)

func sample_input():
	pass # !!!!
	
func send_input_batch():
	pass # !!!!

# Returns an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# 0 means local player, same as get_tree().multiplayer.get_network_unique_id()
func get_input_facade(peer_unique_id:int = 0):
	if peer_unique_id > 0 and get_tree().network_peer and peer_unique_id == get_tree().multiplayer.get_network_unique_id():
		peer_unique_id = 0
	var peer = get_node("%s/SyncInputFacade" % peer_unique_id)
	return peer if peer else FakeInputFacade.new()

# Instantiated instances of SyncBase report here upon creation
func SyncBase_created(sb, spawner=null):
	pass # !!!

# Getters and setters
func get_state_id_frac():
	var result = Engine.get_physics_interpolation_fraction() - state_id_frac_fix
	result = clamp(result, 0.0, 0.99)
	return result + state_id

func set_input_id(_value):
	pass # read-only
func get_input_id():
	return input_id
func set_state_id(_value):
	pass # read-only
func get_state_id():
	return input_id

# Fake SyncInputFacade to return when asked for unknown peer_unique_id
class FakeInputFacade:
	signal _input
	func is_action_pressed(action: String)->bool:
		return false
	func is_action_just_pressed(action: String)->bool:
		return false
	func is_action_just_released(action: String)->bool:
		return false
	func get_action_strength(action: String)->float:
		return 0.0
	func action_press(action: String)->void:
		pass
	func action_release(action: String)->void:
		pass
