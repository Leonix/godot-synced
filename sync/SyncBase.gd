#
# !!! make it sync
# make it auto fill from parent after _physics_process()
# and auto set to parent before _process()
# !!! Property setting to update corresponding property on parent node
# every _process() and _physics_process()
# * will probably have to use crazy stuff like _process_internal()
#

extends Node
class_name SyncBase

# 
# SyncBase is the main workhorse if the library.
# - It acts as data storage container to read from and write to in Game Code scripts.
# - If instanced on server, it automatically creates corresponding scene on Clients.
#   !!! not implemented yet
# - It keeps Client's copy of data updated via RPC.
# - It stores a history of values for everything it syncs.
# - It acts as a proxy for player input, see `get_input()` and `belongs_to_peer_id`
#
# SyncBase is designed to parent one or more SyncProperty child nodes.
# Each SyncProperty child becomes a property (field) on this object accessible
# as normal property. For example, consider the following scene:
#     Player (Player.gd extends Node)
#     Player/synced (SyncBase)
#     Player/synced/position (SyncProperty)
# Then, code in Player.gd may read and write position (both on client and server)
# as follows:
#     onready var synced = $Synced
#     synced.position = Vector2(0, 0) # writes are silently ignored on Client
#     synced.position.x               # reads work as expenced
#
# When setting up SyncProperties, make sure that properties should go higher
# in list of child nodes if expected to change often.
#

# Network peer whose Input commands this object listens to.
# Game logic should set this to appropriate peer_id for objects
# that are normally would read input from Input class or use _input() callback
# 0 here always means local player. null means no one (dummy input).
var belongs_to_peer_id = null

# Should be set by whoever instanced scene containing this before attaching to scene tree.
# Affects how Client-Side-Predicted new entities locate their Server counterparts.
var spawner: SyncBase = null # !!! CSP-created nodes are not implemented yet

# Input facade to read player's input through instead of builtin Input
var input setget ,get_input

# Contains child properties {name:SyncProperty}. Determines sendtable.
# Sorted by sync strategy: UNRELIABLE_SYNC, AUTO_SYNC, RELIABLE_SYNC, DO_NOT_SYNC, CLIENT_OWNED
# Among one strategy, order matches position in node tree.
# Properties should go higher in node tree if expected to transmit more often.
onready var sync_properties = prepare_sync_properties()

# Controls rate of sending input from client to server
var _mtime_when_send_next_frame = 0.0

# Remember per-peer and per-property when did we last sent a reliable state_id to them
var _peer_prop_reliable_state_ids = {}

# Last World State id that has been captured.
var state_id = 1 setget set_state_id, get_state_id

# Last World State id that has been captured.
var state_id_frac setget , get_state_id_frac

# Shenanigans needed to calculate state_id_frac
var _state_id_frac_fix = 0.0
var _first_process_since_physics_process = true

func _ready():
	SyncManager.SyncBase_created(self, spawner)

func _process(_delta):
	if _first_process_since_physics_process:
		if SyncManager.state_id_frac_to_integer_reduction > 0:
			_state_id_frac_fix = move_toward(
				_state_id_frac_fix, 
				Engine.get_physics_interpolation_fraction(), 
				SyncManager.state_id_frac_to_integer_reduction
			)
			_first_process_since_physics_process = false

func prepare_sync_properties():
	var result = {}
	var add_later = []
	var add_last = []
	for property in get_children():
		assert(property is SyncProperty, 'All children of SyncBase must be SyncProperty (looking at you, %s)' % property.name)
		if not property.ready_to_write():
			SyncManager.init_sync_property(property)
			match property.sync_strategy:
				SyncProperty.UNRELIABLE_SYNC:
					result[property.name] = property
				SyncProperty.AUTO_SYNC:
					add_later.push_front(property)
				SyncProperty.RELIABLE_SYNC:
					add_later.append(property)
				SyncProperty.DO_NOT_SYNC:
					add_last.push_front(property)
				SyncProperty.CLIENT_OWNED:
					add_last.append(property)
				var unknown_strategy:
					assert(false, 'Unknown sync strategy %s' % unknown_strategy)
	for property in add_later + add_last:
		result[property.name] = property
	return result

func _physics_process(_delta):
	
	# Increment global state time
	state_id += 1
	_first_process_since_physics_process = true
	
	if SyncManager.is_server():
		var time = OS.get_system_time_msecs()
		if _mtime_when_send_next_frame <= time:
			var delay = int(1000 / SyncManager.server_sendrate)
			if time - _mtime_when_send_next_frame > delay:
				_mtime_when_send_next_frame = time + delay
			else:
				_mtime_when_send_next_frame += delay
			send_all_data_frames()

# Pessimistic selection of state_ids last reliably sent to given player (or all players).
# Do not midify Dict returned, make a copy if needed.
func get_last_reliable_state_ids(peer_id=null)->Dictionary:
	if peer_id:
		return _peer_prop_reliable_state_ids.get(peer_id, {})

	var props = {}
	for peer_id in multiplayer.get_network_connected_peers():
		var other_props = _peer_prop_reliable_state_ids.get(peer_id)
		if other_props:
			for prop in other_props:
				if not (prop in props) or props[prop] > other_props[prop]:
					props[prop] = other_props[prop]
	return props

# Send to all clients values of properties belonging to this SyncBase.
# SyncBase sends to all players the same time (but different SyncBases may still
# send at different state_ids).
# If at all possible, SyncBase tries to send to all players the same data
# to save CPU cycles on data encoding. This may not always be possible
# due to Time Depth calculations (!!! not implemented yet)
# and hidden (masked) properties different for different players (!!! again)
func send_all_data_frames():
	
	var can_batch = true

	# Does this object has the same hidden (masked) status for all players?
	# !!!
	
	# Do all values match for all players?
	if can_batch:
		pass # !!!
	
	# If something differs, send each frame separately.
	# If can batch, prepare data for first peer_id and send packet to everyone.
	for peer_id in multiplayer.get_network_connected_peers():

		match prepare_data_frame(get_last_reliable_state_ids(null if can_batch else peer_id)):
			[var sendtable, var reliable_frame, var unreliable_frame]:

				# simulate packet loss
				if SyncManager.simulate_unreliable_packet_loss_percent > 0:
					if rand_range(0, 100) < SyncManager.simulate_unreliable_packet_loss_percent:
						unreliable_frame = null
				
				if unreliable_frame and unreliable_frame.size() > 0:
					#print('!!! sending unreliable frame %s (can_batch=%s) %s ' % [state_id, can_batch, unreliable_frame])
					var data = pack_data_frame(sendtable, unreliable_frame)
					var sendtable_ids = data[0]
					if sendtable_ids != null:
						sendtable_ids = PoolIntArray(data[0])
					if can_batch:
						rpc_unreliable('receive_data_frame', state_id, sendtable_ids, data[1])
					else:
						rpc_unreliable_id(peer_id, 'receive_data_frame', state_id, sendtable_ids, data[1])

				if reliable_frame and reliable_frame.size() > 0:
					#print('!!! sending reliable frame %s (can_batch=%s) %s ' % [state_id, can_batch, reliable_frame])
					var data = pack_data_frame(sendtable, reliable_frame)
					var sendtable_ids = data[0]
					if sendtable_ids != null:
						sendtable_ids = PoolIntArray(data[0])
					if can_batch:
						rpc('receive_data_frame', state_id, sendtable_ids, data[1])
						for peer_id2 in multiplayer.get_network_connected_peers():
							if not peer_id2 in _peer_prop_reliable_state_ids:
								_peer_prop_reliable_state_ids[peer_id2] = {}
							for prop in reliable_frame:
								_peer_prop_reliable_state_ids[peer_id2][prop] = state_id
					else:
						rpc_id(peer_id, 'receive_data_frame', state_id, sendtable_ids, data[1])
						if not peer_id in _peer_prop_reliable_state_ids:
							_peer_prop_reliable_state_ids[peer_id] = {}
						for prop in reliable_frame:
							_peer_prop_reliable_state_ids[peer_id][prop] = state_id
		# When data for all peers match, we're done after the first loop iteration
		if can_batch:
			return

# Prepare data frame based on how long ago last reliable frame was sent to a peer
func prepare_data_frame(prop_reliable_state_ids:Dictionary):

	# Gather protocol preference (reliable/unreliable/auto) from all properties
	# and values to be send.
	var frame_reliable = {}
	var frame_unreliable = {}
	var unassigned = {}

	var sendtable = sync_properties.keys()
	for prop in sendtable:
		var property = sync_properties[prop]
		
#		print('%s !!! rel_state_id=%s shouldsend=%s ready=%s' % [prop, \
#			prop_reliable_state_ids.get(prop, 0), 
#			property.shouldsend(prop_reliable_state_ids.get(prop, 0)),
#			property.ready_to_read()
#		])
		
		match property.shouldsend(prop_reliable_state_ids.get(prop, 0)):
			[SyncProperty.CLIENT_OWNED, ..],\
			[SyncProperty.DO_NOT_SYNC, ..]:
				pass
			[SyncProperty.RELIABLE_SYNC, var value]:
				frame_reliable[prop] = value
			[SyncProperty.UNRELIABLE_SYNC, var value]:
				frame_unreliable[prop] = value
			[SyncProperty.AUTO_SYNC, var value]:
				unassigned[prop] = value
			null, false:
				pass
			var unknown_shouldsend:
				assert(false, 'SyncProperty.shouldsend() returned unexpected value %s' % unknown_shouldsend)

	# Append AUTO_SYNC to where needed
	if unassigned.size() > 0:
		if frame_reliable.size() > 0:
			for prop in unassigned:
				frame_reliable[prop] = unassigned[prop]
		else:
			for prop in unassigned:
				frame_unreliable[prop] = unassigned[prop]

	return [sendtable, frame_reliable, frame_unreliable]

# Called via RPC, sending data from Server to all Clients.
puppet func receive_data_frame(st_id, sendtable_ids, values):
	if SyncManager.simulate_network_latency != null:
		var delay = rand_range(SyncManager.simulate_network_latency[0], SyncManager.simulate_network_latency[1])
		yield(get_tree().create_timer(delay), "timeout")
	var frame = parse_data_frame(sync_properties.keys(), sendtable_ids, values)
	#print('!!! received frame %s %s %s %s' % [st_id, sendtable_ids, values, frame])
	for prop in frame:
		sync_properties[prop].write(st_id, frame[prop])

# Tightly pack data frame before sending
# `sendtable` is an Array of Property names (strings) used to encode values.
# Sendtable is generated locally, required to be the same on both Client and Server.
# Array(int) of `sendtable_ids` contains indices in sendtable.
# Array of `values` contains corresponsing values.
# There may be more `values` than there are indices. Rest of `values`, 
# however many there is, correspond to indices from the start of the sendtable -
# this trick saves a few bytes of traffic per frame.
static func pack_data_frame(sendtable:Array, frame:Dictionary):
	var sendtable_ids = []
	var values_no_id = []
	var values = []
	var sendtable_id = -1
	var must_use_id = false
	for prop in sendtable:
		sendtable_id += 1
		if not (prop in frame):
			must_use_id = true
			continue
		if must_use_id:
			sendtable_ids.append(sendtable_id)
			values.append(frame[prop])
		else:
			values_no_id.append(frame[prop])
	#values.append_array(values_no_id) # this raises for some reason Invalid call. Nonexistent function 'append_array' in base 'Array'.
	values += values_no_id
	return [
		sendtable_ids if sendtable_ids.size() else null, 
		values if values.size() else null
	]

# Reverse pack_data_frame() called at receiving end.
static func parse_data_frame(sendtable:Array, sendtable_ids, values)->Dictionary:
	assert(sendtable_ids == null or sendtable_ids is Array or sendtable_ids is PoolIntArray)
	assert(values == null or values is Array)
	var result = {}
	if values == null:
		return result
	var sendtable_index = 0
	var sendtable_ids_index = 0
	for value in values:
		var sendtable_id
		if sendtable_ids != null and sendtable_ids.size() > sendtable_ids_index:
			sendtable_id = sendtable_ids[sendtable_ids_index]
			sendtable_ids_index += 1
		else:
			assert(sendtable.size() > sendtable_index, "Too many values")
			sendtable_id = sendtable_index
			sendtable_index += 1
		result[sendtable[sendtable_id]] = value
	return result

# Returns object to serve as a drop-in replacement for builtin Input to proxy
# player input through. On server, this receives remote input over the net.
# Objects belonging to local player on both client and server will receive local input.
# This requires `belongs_to_peer_id` field to be properly set.
func get_input():
	if not input or input.get_peer_id() != belongs_to_peer_id:
		input = SyncManager.get_input_facade(belongs_to_peer_id)
	return input

func is_local_peer():
	return belongs_to_peer_id == 0

# Getters and setters
func get_state_id_frac():
	if Engine.is_in_physics_frame():
		return float(state_id)
	var result = Engine.get_physics_interpolation_fraction() - _state_id_frac_fix
	result = clamp(result, 0.0, 0.99)
	return result + state_id

func set_state_id(_value):
	pass # read-only
func get_state_id():
	return state_id

func default_read_state_id():
	if not SyncManager.is_client():
		return -1

	# !!! TODO implement interpolation on client
	return -1

func default_write_state_id():
	return state_id

func _get(prop):
	var p = sync_properties.get(prop)
	if p:
		assert(p.ready_to_read(), "Attempt to read from %s:%s before any writes happened" % [get_path(), prop])
		return p.read(default_read_state_id())

func _set(prop, value):
	var p = sync_properties.get(prop)
	if p:
		assert(p.ready_to_write(), "Improperly initialized SyncProperty %s:%s" % [get_path(), prop])
		p.write(default_write_state_id(), value)
		return true
