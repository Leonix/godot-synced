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

# Input sendtable maps numbers (int) to InputMap actions (String) to use
# for communication between client and server. Sendtable on client 
# must exactly match sendtable on server.
onready var input_sendtable = parse_input_map(InputMap)

# Whether connection to server is currently active. Only maintained on Client.
var _is_connected_to_server = false

func _ready():
	get_local_peer()
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")
	get_tree().connect("connected_to_server", self, "_i_connected")
	get_tree().connect("server_disconnected", self, "_i_disconnected")

func _process(_delta):
	if first_process_since_physics_process and state_id_frac_to_integer_reduction > 0:
		state_id_frac_fix = move_toward(state_id_frac_fix, Engine.get_physics_interpolation_fraction(), state_id_frac_to_integer_reduction)
		first_process_since_physics_process = false

func is_server():
	return get_tree().network_peer and get_tree().is_network_server()

func is_client():
	return get_tree().network_peer and _is_connected_to_server and not get_tree().is_network_server()

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
		if (time - _mtime_last_input_batch_sent) * input_sendrate * input_sendrate >= 1000.0*(input_sendrate-.5):
			_mtime_last_input_batch_sent = time
			send_input_batch()

# Helper to initialize sendtable based on InputMap
func parse_input_map(input_map):
	var send_as_bool = []
	var send_as_float = []

	for action in input_map.get_actions():
		# ignore ip actions as client-only
		if action.substr(0, 3) == 'ui_':
			continue
		var added = false
		# To determine type of each action (send as float or as bool)
		# we look for  among event types
		for event in input_map.get_action_list(action):
			if event is InputEventJoypadMotion:
				send_as_float.append(action)
				added = true
				break
		if not added:
			send_as_bool.append(action)

	send_as_float.sort()
	send_as_bool.sort()
	
	return {
		"float": send_as_float,
		"bool": send_as_bool,
	}
	
func sample_input():
	var result =  {}
	for type in input_sendtable:
		for action in input_sendtable[type]:
			match type:
				'bool':
					result[action] = Input.is_action_pressed(action)
				'float':
					result[action] = Input.get_action_strength(action)
				_:
					assert(false, "Unknown input action class '%s'" % type)
	get_local_peer().storage.write(input_id, result)

func send_input_batch():
	var storage = get_local_peer().storage
	if not storage.ready_to_read():
		return # paranoid check

	assert(is_client())
	assert(storage.container.size() >= self.input_frames_min_batch, 'input_frames_min_batch can not be less than input_frames_history_size')

	var frames = []
	var first_input_id = storage.last_state_id - self.input_frames_min_batch + 1
	for iid in range(first_input_id, storage.last_state_id+1):
		var frame = storage.read(iid);
		assert(frame is Dictionary, "Unexpected Input Frame from SyncPeer storage")
		frames.append(frame.duplicate())
	
	var packed_batch = pack_input_batch(input_sendtable, frames)
	#print('sending input batch first_input_id=%s ' % first_input_id, frames)
	rpc('receive_input_batch', first_input_id, PoolIntArray(packed_batch[0]), PoolStringArray(packed_batch[1]), packed_batch[2])

master func receive_input_batch(first_input_id: int, sendtable_ids: Array, node_paths: Array, values: Array):
	var frames = parse_input_batch(input_sendtable, sendtable_ids, node_paths, values)
	# !!!
	#print('received input batch first_input_id=%s ' % first_input_id, frames)

static func pack_input_batch(sendtable, frames):
	#
	# (1) All mentioned sendtable entries (one packed array of ints)
	# (2) All mentioned SyncBases (one packed array of strings)
	#  - contains NodePaths relative to `get_tree().current_scene`
	#  - after each nodepath empty string is repeated for each additional 
	#    property beyond first from this nodepath
	# (3) Then Array (untyped) of zero or more Arrays (untyped), one for each state_id in batch.
	#   - (3.1) All boolean values from sendtables (several ints)
	#     May be missing entirely.
	#   - (3.2) All float values from sendtables (one packed array of floats)
	#     May be missing if no floats and no (3.3) are to be sent.
	#   - (3.3) All SyncBase values (several entries, one per string in (2))
	#     May be missing if no client-owned values are to be sent.
	#

	# Figure out which sendtable entries are to be sent.
	# This prepares (1).
	var sendtable_ids = []
	var sendtable_id = 0
	var sendtable_type_by_id = {}
	for type in sendtable:
		for action in sendtable[type]:
			sendtable_id += 1
			for frame in frames:
				if frame[action] != 0:
					sendtable_ids.append(sendtable_id)
					sendtable_type_by_id[sendtable_id] = type
					break
	
	# (2) is not supported yet
	var node_paths = [] 
	
	# (3) pack values
	var values = []
	if sendtable_ids.size() > 0 or node_paths.size() > 0:
		for frame in frames:
			var value = []
			var floats = []
			sendtable_id = 0
			for type in sendtable:
				for action in sendtable[type]:
					sendtable_id += 1
					type = sendtable_type_by_id.get(sendtable_id)
					if type != null:
						if type == 'bool':
							var v = bool(frame[action])
							# !!! TODO pack several bools into each int to save traffic
							value.append(v)
						else:
							assert(type == 'float', 'Unknown sendtable type %s' % type)
							floats.append(float(frame[action]))
					
			# !!! TODO: pack client-owned properties
			var client_owned = []
			
			if floats.size() > 0 or client_owned.size() > 0:
				value.append(PoolRealArray(floats))
			if client_owned.size() > 0:
				value.append(client_owned)
			values.append(value)
	
	return [sendtable_ids, node_paths, values]

static func parse_input_batch(sendtable, sendtable_ids: Array, node_paths: Array, values: Array):
	var sendtable_action_by_id = {}
	for id in sendtable_ids:
		sendtable_action_by_id[id] = null
	
	var sendtable_id = 0
	var empty_frame = {}
	for type in sendtable:
		for action in sendtable[type]:
			sendtable_id += 1
			if type == 'bool':
				empty_frame[action] = 0
			else:
				empty_frame[action] = 0.0
			if sendtable_id in sendtable_action_by_id:
				sendtable_action_by_id[sendtable_id] = action

	var result = []
	
	# when no values came, we assume proper number of empty frames
	if values.size() <= 0:
		for __ in range(SyncManager.input_frames_min_batch-1):
			result.append(empty_frame.duplicate())
		result.append(empty_frame)
		return result
	
	for value in values:
		var bools = []
		var floats = null
		var client_owned = null
		for v in value:
			match typeof(v):
				TYPE_BOOL:
					bools.append(int(v))
				TYPE_INT:
					# !!! TODO: unpack several bools from int when implemented
					bools.append(int(v))
				_:
					if floats == null:
						assert((v is Array) or (v is PoolRealArray), 'Array of floats expected')
						floats = v
					else:
						assert(v is Array, 'Array expected')
						assert(client_owned == null, 'Too much data')
						client_owned = v

		var frame = empty_frame.duplicate()
		var bool_i = 0
		var float_i = 0
		sendtable_id = 0
		for type in sendtable:
			for action in sendtable[type]:
				sendtable_id += 1
				if sendtable_id in sendtable_action_by_id:
					if type == 'bool':
						assert(bool_i < bools.size(), 'Not enough booleans in Input frame batch')
						frame[action] = bools[bool_i]
						bool_i += 1
					else:
						assert(type == 'float', 'Unknown sendtable type %s' % type)
						assert(floats != null and float_i < floats.size(), 'Not enough floats in Input frame batch')
						frame[action] = floats[float_i]
						float_i += 1
		result.append(frame)
		assert((float_i == 0 and floats == null) or float_i == floats.size(), "Too much floats in input frame batch")
		assert(node_paths.size() <= 0, "Sending Client-Owned Properties is not implemented yet") # !!!
	return result
	

# Returns an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# 0 means local player, same as get_tree().multiplayer.get_network_unique_id()
func get_input_facade(peer_unique_id:int = 0):
	if peer_unique_id > 0 and get_tree().network_peer and peer_unique_id == get_tree().multiplayer.get_network_unique_id():
		peer_unique_id = 0
	var peer = get_node("%s/SyncInputFacade" % peer_unique_id)
	return peer if peer else SyncInputFacade.FakeInputFacade.new()

# Instances of SyncBase report here upon creation
func SyncBase_created(_sb, _spawner=null):
	pass # !!!

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
		local_peer = SyncPeer.instance()
		local_peer.name = '0'
		self.add_child(local_peer)

	return local_peer

# Signals from scene tree networking
func _player_connected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = SyncPeer.instance()
		peer.name = str(peer_id)
		self.add_child(peer)

func _player_disconnected(peer_id=null):
	if is_server() and peer_id > 0:
		var peer = get_node(str(peer_id))
		if peer:
			peer.queue_free()

func _i_connected():
	_is_connected_to_server = true

func _i_disconnected():
	_is_connected_to_server = false

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
