extends Node

#
# Synced lib requires this class to be autoloaded as SyncManager singleton.
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
# This must exceed client_interpolation_lag plus max latency
var client_interpolation_history_size = 40

# When switching to CSP, clients will smooth slow down over this many times their latency
var client_csp_period_multiplier = 3.0

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

# SyncSequence is responsible for state_id and input_id management between client and server
var seq:SyncSequence = SyncSequence.new(self)

func _ready():
	get_local_peer()
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("server_disconnected", self, "_i_disconnected")

func _process(delta):
	seq._process(delta)

func _physics_process(delta):
	seq._physics_process(delta)

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
func synced_created(synced:Synced, _spawner=null):
	synced.connect("peer_id_changed", seq, "update_synced_belong_to_players", [synced])
	if synced.belongs_to_peer_id != null:
		seq.update_synced_belong_to_players(null, synced.belongs_to_peer_id, synced)
	
	# Remember this Synced if it contains a client-owned property
	for prop in synced.synced_properties:
		var p:SyncedProperty = synced.synced_properties[prop]
		if p and p.ownership == SyncedProperty.OWNERSHIP_CLIENT_IF_PEER:
			_synced_with_client_owned[str(
				get_tree().get_root().get_path_to(synced.get_parent())
			)] = weakref(synced)
			break

# All Synced objects with at least one client-owned property; node path from current scene => weakref
var _synced_with_client_owned = {}

# Update client-owned properties using input frame that came from client over the network
func update_client_owned_properties(peer_id:int, cop_values: Dictionary)->void:
	assert(SyncManager.is_server() and peer_id != 0)
	var remove = []
	for node_path in _synced_with_client_owned:
		var synced:Synced = (_synced_with_client_owned[node_path] as WeakRef).get_ref()
		if synced == null:
			remove.append(node_path)
		elif node_path in cop_values and synced.belongs_to_peer_id == peer_id:
			synced.set_client_owned_values(cop_values[node_path])
	for node_path in remove:
		_synced_with_client_owned.erase(node_path)

# Get all tracked client-owned propoerties to add to client input frame
func sample_client_owned_properties()->Dictionary:
	assert(SyncManager.is_client())
	var values = {}
	var remove = []
	for node_path in _synced_with_client_owned:
		var synced:Synced = (_synced_with_client_owned[node_path] as WeakRef).get_ref()
		if synced == null:
			remove.append(node_path)
		elif synced.is_local_peer():
			# Will return empty v when not ready to read yet; ignore
			var v = synced.get_client_owned_values()
			if v and v.size() > 0:
				values[node_path] = v

	for node_path in remove:
		_synced_with_client_owned.erase(node_path)
	return values

# Common helper to get coordinate of Spatial and Node2D in a similar way
func get_coord(obj):
	if obj is Spatial:
		return obj.to_global(Vector3(0, 0, 0))
	elif obj is Node2D:
		return obj.to_global(Vector2(0, 0))

var SyncPeerScene = preload("res://addons/synced/SyncPeer.tscn")
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

# Fetch remote or local SyncPeer by id
func get_peer(peer_id:int):
	return get_node(str(peer_id))

# Signals from scene tree networking
func _player_connected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = SyncPeerScene.instance()
		peer.name = str(peer_id)
		self.add_child(peer)
	elif not is_server() and peer_id == 1:
		_is_connected_to_server = true
		seq.reset_client_connection_stats()

func _player_disconnected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = get_node(str(peer_id))
		if peer:
			peer.queue_free()

func _i_disconnected():
	_is_connected_to_server = false
