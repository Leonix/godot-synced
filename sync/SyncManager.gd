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

#
# Example net config of calculation.
# * All assuming Engine.iterations_per_second=60
# * Design goal is smooth interpolation that can tolerate 1 frame of packet loss.
# * Suppose we want server_sendrate = 20. Server sends state every 3 frames.
# * If 1 packet is lost, client will have to cope with a 'hole' of 6 frames 
#   with no data from server.
# * This is compensated by Client Interpolation. Therefore,
#       client_interpolation_lag = 6
#   (which is 0.1 sec)
# * client_interpolation_history_size has to exceed client_interpolation_lag.
#        = 7
# * Another example. Suppose we have resources send more data from server.
#       server_sendrate = 30 # instead of 20
# * In case of 1 frame of packet loss client now has a 'hole' of 4 frames.
#       client_interpolation_lag = 4
# * client_interpolation_history_size = 5
# * That said, it's perfectly fine to drop a design goal of perfectly smooth
#   interpolation in case of packet loss. You can sacrifice smoothness
#   and decrease client_interpolation_lag lower.

# Client will intentionally lag behind last known server state for this many state_ids,
# rendering game world slightly in the past.
# This allows for smooth interpolation between two server states.
# This should be set so that interpolation can proceed even when one frame of
# network data from server gets dropped. This should be a hardcoded setting
# and should be equal between client and server.
# I.e. Engine.iterations_per_second * 2 / server_sendrate
var client_interpolation_lag = 6

# How long (in state_ids) should history be for each interpolated property on a client.
# This must exceed client_interpolation_lag.
var client_interpolation_history_size = 8

# How many times per second to send property values from Server to Client.
var server_sendrate = 20

# How long (in state_ids) should history be for each property on a server.
# This determines max lag-compensation span and max time depth.
# Changing this will only affect newly created Synced objects.
# Only change before scene is loaded.
var server_property_history_size = 60

# How many times per second to send batches of input frames from client on server.
# Client samples at a rate of Engine.iterations_per_second and buffers sampled frames.
# Client sends batches to Server at this rate.
var input_sendrate = 30

# Batch size when sending input frames. This number of frames is sent at input_sendrate.
# In case input_frames_min_batch * input_sendrate exceeds Engine.iterations_per_second
# it adds redundancy, improving tolerance to packet loss, at the cost of increased traffic.
var input_frames_min_batch = 3

# Server: max number of frames to pool for later processing.
# (input_frames_history_size-2) * input_sendrate should exceed Engine.iterations_per_second
# input_frames_history_size must exceed input_frames_min_batch.
var input_frames_history_size = 7

# Server: when no input frames are ready from peer at the moment of consumption,
# server is allowed to copy last valid frame this many times.
# Reasonable value allows to tolerate 1-2 input packets go missing.
var input_prediction_max_frames = 4

# We want first call to _process() after _physics_process() 
# to see integer state_id_frac. But we don't want to interfere
# too much with regularity of state_id_frac. The greater this setting is,
# the stronger we try to make first state_id_frac into integer,
# at the cost of possible large jumps in state_id_frac value
# visible inside _process().
# 1 will force state_id_frac to be integer first time after _physics_process().
# 0 will disable trying to change state_id_frac.
var state_id_frac_to_integer_reduction = 0.04

# Max state_ids client is allowed to extrapolate without data from server
var max_offline_extrapolation = 20

# Delays processing of received packets on Client by this many seconds,
# simulating network latency. Array of two floats means [min,max] sec, 
# null to disable. This applies only once, delaying server->client traffic.
# Client->server traffic is unaffected.
var simulate_network_latency = null # [0.2, 0.3]

# Refuses to deliver this percent of unreliable packets at random.
# Simulates network packet loss. Applies both to sync (server->client)
# and input (client->server) packets.
var simulate_unreliable_packet_loss_percent = 0.0

# Server: last World State that's been processed (or being processed)
# Client: our best guess what's current World State id on server.
var state_id = 1 setget set_state_id, get_state_id

# Same as state_id, smoothed out into float during _process() calls
var state_id_frac: float setget , get_state_id_frac

#
# Private vars zone
#

var SyncPeerScene = preload("res://sync/SyncPeer.tscn")

func _ready():
	get_local_peer()
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("server_disconnected", self, "_i_disconnected")

func _process(_delta):
	fix_state_id_frac()

func _physics_process(_delta):
	_first_process_since_physics_process = true

	# Increment global state time
	state_id += 1
	# Fix clock desync
	if SyncManager.is_client():
		state_id = fix_current_state_id(state_id)
		_input_id_to_state_id.write(get_local_peer().input_id, state_id)

	# Server: update Client-owned properties of all Synced objects, 
	# taking them from new input frame from each client
	if is_server():
		pass # !!!

# Called from SyncPeer. RPC goes through this proxy rather than SyncPeer itself
# because of differences in node path between server and client.
master func receive_input_batch(first_input_id: int, first_state_id: int, sendtable_ids: Array, node_paths: Array, values: Array):
	var peer = get_sender_peer()
	if peer:
		peer.receive_input_batch(first_input_id, first_state_id, sendtable_ids, node_paths, values)

# Returns an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# 0 means local player, same as get_tree().multiplayer.get_network_unique_id()
func get_input_facade(peer_unique_id):
	if peer_unique_id == null:
		return SyncInputFacade.FakeInputFacade.new()
	if peer_unique_id > 0 and get_tree().network_peer and peer_unique_id == get_tree().multiplayer.get_network_unique_id():
		peer_unique_id = 0
	# find_node() avoids warnings on client from get_node() that node does not exist
	var peer = find_node(str(peer_unique_id), false, false)
	if not peer:
		return SyncInputFacade.FakeInputFacade.new()
	return get_node("%s/SyncInputFacade" % peer_unique_id)

# Instances of Synced report here upon creation
func synced_created(_sb, _spawner=null):
	pass # !!! will be needed for client-owned propoerties

# Used to sync server clock and client clock.
# Only maintained on Client
var _old_received_state_id = 0
var _last_received_state_id = 0
var _old_received_state_mtime = 0
var _last_received_state_mtime = 0

# Maintain stats to calculate a running average
# for server tickrate over (up to) last 1000 frames
func update_received_state_id_and_mtime(new_server_state_id):
	if _last_received_state_id >= new_server_state_id:
		return
	_last_received_state_id = new_server_state_id
	_last_received_state_mtime = OS.get_system_time_msecs()
	if _old_received_state_id == 0:
		_old_received_state_id = _last_received_state_id
		_old_received_state_mtime = _last_received_state_mtime
		return
	var new_state_diff = _last_received_state_id - _old_received_state_id
	var new_time_diff = _last_received_state_mtime - _old_received_state_mtime
	if new_state_diff > 1000:
		_old_received_state_id = _last_received_state_id - 1000
		_old_received_state_mtime = _last_received_state_mtime - (new_time_diff * 1000.0 / new_state_diff)

# On Client, CSP correction must remember when we recorded each input frame
onready var _input_id_to_state_id = SyncPeer.CircularBuffer.new(int(max(client_interpolation_history_size, input_frames_history_size)), 0)
	
func input_id_to_state_id(input_id:int):
	assert(is_client())
	if not _input_id_to_state_id.contains(input_id):
		return null
	return _input_id_to_state_id.read(input_id)

# We use a special peer_id=0 to designate local peer.
# This saves hustle in case get_tree().multiplayer.get_network_unique_id()
# changes when peer connects and disconnects.
# Local peer exists, InputFacade is safe to use even when multiplayer is disabled.
func get_local_peer():
	var local_peer
	
	# This check allows to avoid "node nont found" warning when called from _ready
	if get_child_count() > 0:
		local_peer = get_node("0")
	
	if not local_peer:
		local_peer = SyncPeerScene.instance()
		local_peer.name = '0'
		self.add_child(local_peer)

	return local_peer

# True if networking enabled and we're the Server
func is_server():
	return get_tree() and get_tree().network_peer and get_tree().is_network_server()

# Whether connection to server is currently active. Only maintained on Client.
var _is_connected_to_server = false

# True if networking enabled and we're a Client
func is_client():
	return get_tree() and get_tree().network_peer and _is_connected_to_server and not get_tree().is_network_server()

# Returns a SyncPeer child of SyncManager that sent an RPC that is currently
# being processed, or null if no RPC in progress or peer not found for any reason.
func get_sender_peer():
	var peer_id = multiplayer.get_rpc_sender_id()
	if peer_id <= 0:
		return null
	return get_node(str(peer_id))

func get_peer(peer_id:int):
	return get_node(str(peer_id))

# Shenanigans needed to calculate state_id_frac
var _state_id_frac_fix = 0.0
var _first_process_since_physics_process = true

func fix_state_id_frac():
	# try to make first call to _process() after _physics_process()
	# always give integer state_id_frac !!!!
	if _first_process_since_physics_process and SyncManager.state_id_frac_to_integer_reduction > 0:
		_first_process_since_physics_process = false
		_state_id_frac_fix = move_toward(
			_state_id_frac_fix, 
			Engine.get_physics_interpolation_fraction(), 
			SyncManager.state_id_frac_to_integer_reduction
		)

# This scary logic figures out if client should skip some state_ids
# or wait and render state_id two times in a row. This is needed in case
# of clock desync between client and server, or short network failure.
func fix_current_state_id(st_id:int)->int:
	assert(is_client())
	var should_be_current_state_id = int(clamp(st_id, _last_received_state_id, _last_received_state_id + SyncManager.client_interpolation_lag))
	if abs(should_be_current_state_id - st_id) > SyncManager.client_interpolation_lag + SyncManager.max_offline_extrapolation:
		# Instantly jump if difference is too large
		st_id = should_be_current_state_id
	else:
		# Gradually move towards proper value
		st_id = int(move_toward(st_id, should_be_current_state_id, 1))
	# Refuse to extrapolate more than allowed by global settings
	if st_id > _last_received_state_id + SyncManager.max_offline_extrapolation:
		st_id = _last_received_state_id + SyncManager.max_offline_extrapolation
	return st_id

func set_state_id(_value):
	pass # read-only
func get_state_id():
	return state_id

# Getters and setters
func get_state_id_frac():
	if Engine.is_in_physics_frame():
		return float(state_id)
	var result = Engine.get_physics_interpolation_fraction() - _state_id_frac_fix
	result = clamp(result, 0.0, 0.99)
	return result + state_id

func get_interpolation_state_id():
	assert(is_client())
	return max(1, get_state_id_frac() - SyncManager.client_interpolation_lag)

func init_sync_property(p):
	if is_client():
		p.resize(client_interpolation_history_size)
	else:
		p.resize(server_property_history_size)
	return p

# Signals from scene tree networking
func _player_connected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = SyncPeerScene.instance()
		peer.name = str(peer_id)
		self.add_child(peer)
	elif not is_server() and peer_id == 1:
		_is_connected_to_server = true
		_last_received_state_mtime = 0
		_old_received_state_mtime = 0
		_last_received_state_id = 0
		_old_received_state_id = 0
		state_id = 1

func _player_disconnected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = get_node(str(peer_id))
		if peer:
			peer.queue_free()

func _i_disconnected():
	_is_connected_to_server = false
