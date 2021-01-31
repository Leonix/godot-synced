extends Node
class_name SyncPeer

# Script for SyncPeer.tscn scene.
# Scene holds data structures for one network peer. 
# Instanced as children of SyncManager for each network peer.
# SyncPeer designated to local player is a special one. Local peer samples input 
# and sends to server in batches of several frames (if on Client).
# Remote peers on server receive batches and feed input to game logic.
# SyncPeer with Node.name=='0' always exists on both client and server,
# even when no network is initialized, and maps to local peer.
# Remote SyncPeers only exist on server and have Node.name equal to their network_peer_id.
# Remote SyncPeers are added and removed as clients connect and disconnect from server.

# Input facade is an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# It unifies for Game Logic reading input from local and remote peers.
onready var facade = $SyncInputFacade

# Local peer on both client and server: last input frame that has been captured.
# Remote peer on server: last input frame that has been processed from this peer
# (or is being processed if we're in _physics_processs())
# This is used by InputFacade to consume input from peers at the same rate 
# they generate it.
var input_id = 0
var stale_input_frame_count = 0

# Local peer: state_id during last sampled input
# Remote peer: World State id visible on remote client during generation 
# of last processed (or current being processed) input frame
var state_id setget set_state_id, get_state_id

# Input sendtable maps numbers (int) to InputMap actions (String) to use
# for communication between client and server. Sendtable on client 
# must exactly match sendtable on server.
onready var input_sendtable = parse_input_map(InputMap)

# Buffer stores a history of input frames from both local peer and remote peers. 
# Each input frame is a Dictionary mapping Input action name(String) to value(int or float).
onready var storage = CircularBuffer.new(SyncManager.input_frames_history_size, get_empty_input_frame())

# Used on a local peer to control rate of sending input from client to server
var _mtime_last_input_batch_sent = 0.0

func _physics_process(_delay):
	if is_local():
		# Build new Input frame
		input_id += 1
		storage.write(input_id, sample_input())

		# Client: send input frames to server if time has come
		if SyncManager.is_client():
			var delay = OS.get_system_time_msecs() - _mtime_last_input_batch_sent
			var target_delay = 1000.0 / SyncManager.input_sendrate
			if delay >= target_delay:
				if delay >= 2*target_delay:
					_mtime_last_input_batch_sent = OS.get_system_time_msecs()
				else:
					_mtime_last_input_batch_sent += delay
				send_input_batch()

	if not is_local():
		# read next input frame from the client, if it came
		if storage.last_input_id > input_id:
			input_id += 1
			stale_input_frame_count = 0
		else:
			stale_input_frame_count += 1
			# Only allow to copy last input frame for so much.
			# If no data from client for too long, insert an empty input frame
			if stale_input_frame_count > SyncManager.input_prediction_max_frames:
				input_id += 1
				stale_input_frame_count = 1
				storage.write(input_id, get_empty_input_frame())

		# Skip input frames if too many comes from the client for any reason.
		# Simple strategy: skip all input frames we have lost data for.
		# Short storage buffer size will keep clients from large input lag.
		# !!! Skipping random frames has a major downside that server may miss
		# an occasional just_pressed or just_released
		if input_id-2 <= storage.last_input_id - storage.container.size():
			input_id = storage.last_input_id + 1 - SyncManager.input_frames_min_batch

		# TODO: it is possible to invent more complicated srategies, like skipping 
		# current frame if it matches either previous or the next one...
		# At this point it feels premature to try that.

# True if server did not have enough input frames from client this frame
# and had to fall back to previous one. We disable correction of 
# client-side-predicted values for such frames.
func is_stale_input():
	return not is_local() and bool(stale_input_frame_count)

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

func send_input_batch():
	assert(is_local() and SyncManager.is_client())
	assert(storage.container.size() >= SyncManager.input_frames_min_batch, 'input_frames_min_batch can not be less than input_frames_history_size')

	# simulate packet loss
	if SyncManager.simulate_unreliable_packet_loss_percent > 0:
		if rand_range(0, 100) < SyncManager.simulate_unreliable_packet_loss_percent:
			return

	var frames = []
	var first_input_id = storage.last_input_id - SyncManager.input_frames_min_batch + 1
	for iid in range(first_input_id, storage.last_input_id+1):
		var frame = storage.read(iid);
		assert(frame is Dictionary, "Unexpected Input Frame from SyncPeer storage")
		frames.append(frame.duplicate())

	var packed_batch = pack_input_batch(input_sendtable, frames)
	#print('sending input batch first_input_id=%s ' % first_input_id, frames)
	SyncManager.rpc_unreliable('receive_input_batch', 
		first_input_id, 
		SyncManager.input_id_to_state_id(first_input_id),
		PoolIntArray(packed_batch[0]), 
		PoolStringArray(packed_batch[1]), 
		packed_batch[2]
	)

func receive_input_batch(first_input_id: int, first_state_id: int, sendtable_ids: Array, node_paths: Array, values: Array):
	assert(not is_local())
	var frames = parse_input_batch(input_sendtable, sendtable_ids, node_paths, values)
	for i in range(frames.size()):
		frames[i]['__client_state_id__'] = first_state_id + i
		storage.write(first_input_id + i, frames[i])

static func pack_input_batch(sendtable, frames):
	#
	# (1) All mentioned sendtable entries (one packed array of ints)
	# (2) All mentioned Synced node paths (one packed array of strings)
	#  - contains NodePaths relative to `get_tree().current_scene`
	#  - after each nodepath empty string is repeated for each additional 
	#    property beyond first from this nodepath
	# (3) Then Array (untyped) of zero or more Arrays (untyped), one array
	#     for each input_id in batch. Each array contains:
	#   - (3.1) All boolean values from sendtables (several ints)
	#     May be missing entirely.
	#   - (3.2) All float values from sendtables (one packed array of floats)
	#     May be missing if no floats and no (3.3) are to be sent.
	#   - (3.3) All Synced values (several entries, one per string in (2))
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

func sample_input():
	assert(is_local())
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
	return result

func get_empty_input_frame():
	var empty_frame = {}
	for type in input_sendtable:
		for action in input_sendtable[type]:
			if type == 'bool':
				empty_frame[action] = 0
			else:
				empty_frame[action] = 0.0
	return empty_frame

func is_local():
	return self.name == '0'

func get_state_id()->int:
	if not is_local():
		# Shenanigans here require some explanation...
		# Clients report their current rendered state_id with every input frame.
		# We want to impose reasonable limits to how server accepts them.
		# Clients should not be able to mess up with Time Depth by instantly changing
		# how server perceives client's ping. Yet, we can't just always force
		# sequential numbers because clock desync happens between client and server
		# all the time, and loyal clients may require to skip or regain their
		# state_id.
		var curr_reported_state_id = facade._get_value('__client_state_id__', -1)
		var prev_reported_state_id = facade._get_value('__client_state_id__', -2)
		var prev2_reported_state_id = facade._get_value('__client_state_id__', -3)
		if not curr_reported_state_id or not prev_reported_state_id or not prev2_reported_state_id or not storage.contains(input_id - 1):
			if curr_reported_state_id:
				return int(curr_reported_state_id)
			return 0
		if curr_reported_state_id == 1+prev_reported_state_id and prev_reported_state_id==1+prev2_reported_state_id:
			# Nothing suspicious: three consecutive state_ids
			return int(curr_reported_state_id)
		# For suspicious frames, we force state_id calculated from an older value
		# in hope to make it unprofitable to cheat by trying to change reported state_id
		if storage.contains(input_id - 2):
			return int(prev2_reported_state_id)+2
		else:
			return int(prev_reported_state_id)+1
	return SyncManager.state_id
func set_state_id(_value):
	pass # read only

# Maps input_id to values, up to buffer size.
# In case of SyncPeer, values are Dictionaries with input data.
# This is also used in Synced to map input_ids to state_ids
class CircularBuffer:

	# Storage place for historic values.
	# This is used as a circular buffer. We keep track of last written index self.last_index,
	# and loop over when reach the end of allocated container space.
	# Contains consecutive values for all integer state_ids ending with self.last_input_id
	# The earliest value we know is always at `self.last_index+1` (possibly loop over),
	# and the earliest value always corresponds to `self.last_input_id - container.size() + 1`
	var container: Array
	# Index in self.container that contains data for the most recent input_id
	# -1 here means the property has never been written to yet.
	var last_index: int = 0
	# input_id written at container[last_index]
	var last_input_id: int = 0

	func _init(size, value):
		container = []
		container.resize(size)
		for i in range(size):
			container[i] = value

	# Returns value at given input_id
	func read(input_id: int):
		return container[_get_index(relative_input_id(input_id))]

	# Write property value at given input_id.
	# Overwrites historic value or adds a new input_id.
	# Write is ignored if input_id is too old.
	func write(input_id: int, value):

		# write to past long gone is silently ignored
		if input_id < last_input_id - container.size() + 1:
			return

		# Overwrite historic value from the not-so-long-ago
		if input_id <= last_input_id:
			container[_get_index(input_id)] = value
			return

		var new_last_input_id = input_id
		var old_last_input_id = last_input_id
		var old_last_value = container[last_index]

		# Fill in values we have skipped between old_last_input_id and new_last_input_id.
		# This maintains that container is tightly packed and no input_id is missing a place.

		# Loop starting from self.last_index+1 up to (wrappig over) self.last_index-1
		# for how many iterations are needed. (Leave space for last value itself).
		var loop_iterations_count = new_last_input_id - old_last_input_id - 1
		# Loop iteration count can not exceed size of container
		loop_iterations_count = clamp(loop_iterations_count, 0, container.size()-1)

		for _i in range(loop_iterations_count):
			last_index = wrapi(last_index + 1, 0, container.size())
			container[last_index] = old_last_value

		# Finally, write the new_last_input_id value
		last_input_id = new_last_input_id
		last_index = wrapi(last_index + 1, 0, container.size())
		container[last_index] = value

	# Closest index to given input_id.
	func _get_index(input_id: int)->int:
		input_id = int(clamp(input_id, last_input_id - container.size() + 1, last_input_id))
		return wrapi(last_index - last_input_id + input_id, 0, container.size())

	# helper to normalize negative indices
	func relative_input_id(input_id:int)->int:
		if input_id < 0:
			var result = last_input_id + 1 + input_id
			return result if result > 0 else 1
		return input_id

	# whether buffer contains value for given input_id
	func contains(input_id: int):
		return input_id == int(clamp(input_id, last_input_id - container.size() + 1, last_input_id))
