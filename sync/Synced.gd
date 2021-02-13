extends Node
class_name Synced

# 
# `Synced` is the main workhorse if the library.
# - It acts as data storage container to read from and write to in Game Code scripts.
# - If instanced on server, it automatically creates corresponding scene on Clients.
#   !!! not implemented yet
# - It keeps Client's copy of data updated via RPC.
# - It stores a history of values for everything it syncs.
# - It acts as a proxy for player input, see `get_input()` and `belongs_to_peer_id`
#
# `Synced` is designed to parent one or more SyncedProperty child nodes.
# Each SyncedProperty child becomes a property (field) on this object accessible
# as normal property. For example, consider the following scene:
#     Player (Player.gd extends Node)
#     Player/synced (Synced)
#     Player/synced/position (SyncedProperty)
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
var belongs_to_peer_id = null setget set_belongs_to_peer_id

# Even if this Synced belongs to a certain peer, ignore its coordinate
# when calculating time depth. Should be false on players' avatars.
# Safe to leave false on AI-controlled entities.
# Must be true on UI elements if they use belongs_to_peer_id != null.
export var ignore_peer_time_depth = false

# Should be set by whoever instanced scene containing this before attaching to scene tree.
# Affects how Client-Side-Predicted new entities locate their Server counterparts.
var spawner: Synced = null # !!! CSP-created nodes are not implemented yet

# Input facade to read player's input through instead of builtin Input
var input setget ,get_input

# Contains child properties {name:SyncedProperty}. Determines sendtable.
# Sorted by sync strategy: UNRELIABLE_SYNC, AUTO_SYNC, RELIABLE_SYNC, DO_NOT_SYNC, CLIENT_OWNED
# Among one strategy, order matches position in node tree.
# Properties should go higher in node tree if expected to transmit more often.
onready var synced_properties = prepare_synced_properties()

# Controls rate of sending input from client to server
var _mtime_when_send_next_frame = 0.0

# Remember per-peer and per-property when did we last sent a reliable state_id to them
var _peer_prop_reliable_state_ids = {}

# Server: true if last time this Synced sent to clients, frame contained at least one value.
# Client: true if last time we received from server, frame contained at least one value.
var _last_frame_had_data = true

# True is there's at least one property that requires to sync directly to parent
var _should_auto_update_parent = false
var _should_auto_read_parent = false

# Set by Aligned sibling if exists. Enables Client-Side prediction for this node.
var is_csp_enabled = false

# Debug helper
export var log_property_values_each_tick = false

# When belongs_to_peer_id changes.
# Arguments are either int or null.
signal peer_id_changed(before, after)

func _ready():
	# make sure there are no other Synced siblings
	assert(_has_no_synced_siblings(), "%s is only allowed to contain one Synced object" % get_parent().get_path())
	
	setup_auto_update_parent()
	SyncManager.synced_created(self, spawner)

# We use process_internal to update parent node just before its _process() runs.
# Only runs on Client if at least one auto-synced property is found.
func _notification(what):
	if what == NOTIFICATION_INTERNAL_PROCESS:
		_auto_sync_all_to_parent()

func _physics_process(_delta):
	# _physics_process() of child nodes runs after parent node.
	# Copy data from parent if set up to do so
	if _should_auto_read_parent:
		for property in get_children():
			if property.auto_sync_property != '':
				if not SyncManager.is_client() or is_client_side_predicted(property) or is_client_owned(property):
					_auto_sync_from_parent(property)

	if SyncManager.is_client():

		_update_prop_csp_tick()

		if not _last_frame_had_data:
			# Last time we received an empty frame from Server.
			# It means that no values changed and likely will not change soon.
			# We're allowed to extrapolate this last known state into the future
			# as if we receive it from server each frame.
			for prop in synced_properties:
				var property:SyncedProperty = synced_properties[prop]
				if is_client_side_predicted(property):
					pass # can't correct prediction errors though
				elif SyncManager.seq.interpolation_state_id > property.last_state_id:
					if property.ready_to_read() and (property.sync_strategy == SyncedProperty.AUTO_SYNC or property.sync_strategy == SyncedProperty.RELIABLE_SYNC):
						if property.debug_log: print('ext_emp_f')
						property.write(SyncManager.seq.interpolation_state_id, property._get(-1))

		if log_property_values_each_tick: for property in get_children():
			if property.debug_log and property.ready_to_read():
				print('%s@%s=%s' % [property.name, SyncManager.seq.interpolation_state_id_frac, property._get(SyncManager.seq.interpolation_state_id_frac)])

	# Send data frame fromo server to clients if time has come
	if SyncManager.is_server():
		var time = OS.get_system_time_msecs()
		if _mtime_when_send_next_frame <= time:
			var delay = int(1000 / SyncManager.server_sendrate)
			if time - _mtime_when_send_next_frame > delay:
				_mtime_when_send_next_frame = time + delay
			else:
				_mtime_when_send_next_frame += delay
			send_all_data_frames()

func _auto_sync_all_to_parent():
	assert(not SyncManager.is_server())
	for property in get_children():
		if property.auto_sync_property != '':
			if property.ready_to_read():
				_auto_sync_to_parent(property)

func _auto_sync_from_parent(property: SyncedProperty):
	assert(property.auto_sync_property)
	var value = get_parent().get(property.auto_sync_property)
	if is_writable(property):
		if property.debug_log: print('autosync_from_parent', value)
		self._set(property.name, value)
	else:
		# revert changes that may have been made by game code
		_auto_sync_to_parent(property)

func _auto_sync_to_parent(property: SyncedProperty):
	assert(property.auto_sync_property)
	#if property.debug_log: print('autosync_to_parent', self._get(property.name))
	get_parent().set(property.auto_sync_property, self._get(property.name))

func setup_auto_update_parent():
	_should_auto_read_parent = false
	_should_auto_update_parent = false
	for property in get_children():
		if property.auto_sync_property != '':
			_should_auto_read_parent = true
			if property.sync_strategy != SyncedProperty.DO_NOT_SYNC:
				_should_auto_update_parent = true
				break
	if not SyncManager.is_server():
		set_process_internal(_should_auto_update_parent)

# Data structures kept on client to track current CSP status of properties
var _prop_force_csp_until_input_id = {}
var _prop_is_server_csp = {}

# Called every frame, as well as on netframe
func _update_prop_csp_tick():
	assert(SyncManager.is_client())
	for prop in _prop_force_csp_until_input_id:
		var input_id = _prop_force_csp_until_input_id[prop]
		if input_id <= SyncManager.seq.last_consumed_input_id:
			_prop_force_csp_until_input_id.erase(prop)

	# Everything that has just disabled its client-side-prediction
	# has to be reverted back to last known valid server state
	for prop in synced_properties:
		var property:SyncedProperty = synced_properties[prop]
		if property.last_rollback_from_state_id > 0 and not is_client_side_predicted(property):
			assert(property.last_rollback_from_state_id >= property.last_rollback_to_state_id)
			var rollback_to = SyncManager.seq.interpolation_state_id - SyncManager.seq.current_latency_in_state_ids
			if property.latest_known_server_state_id > 0 and property.latest_known_server_state_id < rollback_to:
				rollback_to = property.latest_known_server_state_id
			property.rollback(int(rollback_to))
			property.last_rollback_from_state_id = 0
			property.last_rollback_to_state_id = 0
			if property.latest_known_server_state_id > 0:
				property._set(property.latest_known_server_state_id, property.latest_known_server_value)

# Called when data from server comes.
func _update_prop_csp_netframe(enabled_sendtable_ids):
	assert(SyncManager.is_client())
	var sendtable_id = -1
	for prop in synced_properties:
		sendtable_id += 1
		_prop_is_server_csp[prop] = enabled_sendtable_ids and sendtable_id in enabled_sendtable_ids

# Whether client-side prediction is enabled for given property.
# On server this means that recent history for the property has been rolled back.
# On client this means that all writes to property are allowed and show right away,
# and correction is applied later, eventually when data comes from the server.
func is_client_side_predicted(property)->bool:
	if not property is SyncedProperty:
		property = synced_property(property)
	if SyncManager.is_server():
		return SyncManager.seq.state_id < property.last_rollback_from_state_id*2 - property.last_rollback_to_state_id
	if not SyncManager.is_client():
		return false;
		
	var prop = property.name

	# CSP is forced on client at least until input_id that enabled CSP
	# is consumed on server
	if prop in _prop_force_csp_until_input_id:
		var input_id = _prop_force_csp_until_input_id[prop]
		if input_id > SyncManager.seq.last_consumed_input_id:
			return true

	var interp_state_id = SyncManager.seq.interpolation_state_id_frac

	# If server did not confirm CSP status, CSP is disabled after initial period forced above
	if not _prop_is_server_csp.get(prop):
		if property.last_rollback_from_state_id*2 - property.last_rollback_to_state_id > interp_state_id:
			return false
		
	# CSP is disabled on client after a period to smoothly drop required number of states
	return interp_state_id < property.last_rollback_from_state_id + get_csp_smooth_period(property)

func is_client_owned(property:SyncedProperty)->bool:
	return is_local_peer() and property.sync_strategy == SyncedProperty.CLIENT_OWNED

# Client-side-predicted positions under Aligned show with a lag on client
func get_csp_smooth_period(property:SyncedProperty)->int:
	var rollback_period = max(
		SyncManager.seq.current_latency_in_state_ids - SyncManager.client_interpolation_lag, 
		property.last_rollback_from_state_id - property.last_rollback_to_state_id
	)
	assert(rollback_period >= 0)
	return int(rollback_period * SyncManager.client_csp_period_multiplier)

func get_csp_lag(property:SyncedProperty)->float:
	var max_lag = max(
		SyncManager.seq.current_latency_in_state_ids - SyncManager.client_interpolation_lag, 
		property.last_rollback_from_state_id - property.last_rollback_to_state_id
	)
	if max_lag <= 0:
		return 0.0
	var target_state_id = SyncManager.seq.interpolation_state_id_frac
	var smooth_period = get_csp_smooth_period(property)
	return lerp(
		0, 
		max_lag, 
		clamp(
			(target_state_id - property.last_rollback_to_state_id) / smooth_period,
			0, 1
		)
	)

func prepare_synced_properties():
	setup_position_sync()
	var result = {}
	var add_later = []
	var add_last = []
	for property in get_children():
		assert(property is SyncedProperty, 'All children of Synced must be SyncedProperty (looking at you, %s)' % property.name)
		if not property.ready_to_read():
			if SyncManager.is_client():
				property.resize(SyncManager.client_interpolation_history_size)
			else:
				property.resize(SyncManager.server_property_history_size)
		match property.sync_strategy:
			SyncedProperty.UNRELIABLE_SYNC:
				result[property.name] = property
			SyncedProperty.AUTO_SYNC:
				add_later.push_front(property)
			SyncedProperty.RELIABLE_SYNC:
				add_later.append(property)
			SyncedProperty.DO_NOT_SYNC:
				add_last.push_front(property)
			SyncedProperty.CLIENT_OWNED:
				add_last.append(property)
			var unknown_strategy:
				assert(false, 'Unknown sync strategy %s' % unknown_strategy)
	for property in add_later + add_last:
		result[property.name] = property
	return result

# If attached to a Node2D or a Spatial, add Properties that will sync 
# position and rotation (unless already exist)
func setup_position_sync():
	var parent_node = get_parent()
	if not (parent_node is Spatial or parent_node is Node2D):
		return
	var position_property_name = 'translation' if parent_node is Spatial else 'position'
	for prop in [position_property_name, 'rotation']:
		var property = find_node(prop, false, false)
		if property:
			assert(property.auto_sync_property == prop, '"%s" is a built in property name. When you add it manually, it must still auto update "%s" on parent node' % [prop, prop])
		else:
			property = add_synced_property(prop, SyncedProperty.new({
				missing_state_interpolation = SyncedProperty.LINEAR_INTERPOLATION,
				interpolation = SyncedProperty.LINEAR_INTERPOLATION,
				sync_strategy = SyncedProperty.AUTO_SYNC,
				auto_sync_property = prop
			}))

func get_rotation_property()->SyncedProperty:
	return synced_properties.get('rotation')
	
func get_position_property()->SyncedProperty:
	return synced_properties.get('translation' if get_parent() is Spatial else 'position')

func add_synced_property(name, property: SyncedProperty):
	assert(synced_properties == null or property.sync_strategy == SyncedProperty.DO_NOT_SYNC)
	assert(synced_properties == null or not (name in synced_properties))
	property.name = name
	add_child(property)
	if synced_properties != null:
		synced_properties = prepare_synced_properties()
		setup_auto_update_parent()
	return property

# Dictionary {property_name = state_id} with state_ids last reliably sent
# to given player (or all players).
# Do not modify Dict returned, make a copy if needed.
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

# Send to all clients values of properties belonging to this Synced.
# Synced sends to all players the same time (but different Synced objects may still
# send at different state_ids).
# If at all possible, Synced tries to send to all players the same data
# to save CPU cycles on data encoding. This may not always be possible
# because Time Depth calculations and hidden (masked) properties differ
# for different players (!!! masked properties are not implemented yet)
func send_all_data_frames():
	assert(SyncManager.is_server())
	
	var csp_property_ids = null
	var time_depth = null
	if is_csp_enabled:
		# Gather properties that are in client-side predicted mode
		csp_property_ids = []
		var sendtable_id = -1
		for prop in synced_properties:
			sendtable_id += 1
			if is_client_side_predicted(synced_properties[prop]):
				csp_property_ids.append(sendtable_id)
		if csp_property_ids.size() <= 0:
			csp_property_ids = null

		# time depth only makes sense when we have a sibling Aligned
		# i.e. when CSP is enabled
		time_depth = calculate_time_depth()

	# Can not batch Synced objects that have at least one client-side predicted 
	# property because data has to contain input_id which is different for peers.
	var can_batch = csp_property_ids == null

	# Can not batch objects that have different hidden (masked) status 
	# for different players
	if can_batch:
		pass # !!!

	var this_frame_had_data = false
	var state_id = SyncManager.seq.state_id

	# If something differs, send each frame separately.
	# If can batch, prepare data for first peer_id and send packet to everyone.
	for peer_id in multiplayer.get_network_connected_peers():

		var time_depth_relative_to_peer = null
		if time_depth and time_depth[1] != peer_id:
			time_depth_relative_to_peer = time_depth

		match prepare_data_frame(get_last_reliable_state_ids(null if can_batch else peer_id), time_depth_relative_to_peer):
			[var sendtable, var reliable_frame, var unreliable_frame]:

				# simulate packet loss
				var drop_unreliable_frame = false
				if SyncManager.simulate_unreliable_packet_loss_percent > 0:
					if rand_range(0, 100) < SyncManager.simulate_unreliable_packet_loss_percent:
						drop_unreliable_frame = true

				var last_consumed_input_id = null
				if is_csp_enabled:
					var peer = SyncManager.get_peer(peer_id)
					if peer and not peer.is_stale_input():
						last_consumed_input_id = peer.input_id

				var unreliable_frame_has_data = unreliable_frame and unreliable_frame.size() > 0
				var reliable_frame_has_data = reliable_frame and reliable_frame.size() > 0
				this_frame_had_data = this_frame_had_data or reliable_frame_has_data or unreliable_frame_has_data

				if not drop_unreliable_frame and unreliable_frame_has_data:
					var data = pack_data_frame(sendtable, unreliable_frame)
					var sendtable_ids = data[0]
					if sendtable_ids != null:
						sendtable_ids = PoolIntArray(data[0])
					if can_batch:
						rpc_unreliable('receive_data_frame', state_id, last_consumed_input_id, sendtable_ids, data[1], csp_property_ids)
					else:
						rpc_unreliable_id(peer_id, 'receive_data_frame', state_id, last_consumed_input_id, sendtable_ids, data[1], csp_property_ids)

				if reliable_frame_has_data or (_last_frame_had_data and not unreliable_frame_has_data) or last_consumed_input_id:
					
					# When there's no reliable and no unreliable frame, we still need to send
					# an empty packet so that 
					# 1) client knows nothing changed this frame, and/or
					# 2) client receives last_consumed_input_id and csp_property_ids.
					# In case of (1), client otherwise will try to extrapolate. It's like a dot
					# at the end of a sentence. We use reliable for the dot so that
					# we only have to send it once.
					# In case of (2) we don't really need reliable, but things
					# are complicated enough to try to optimize for that too.
					if not reliable_frame_has_data:
						reliable_frame = {} # make sure it's not null
					
					var data = pack_data_frame(sendtable, reliable_frame)
					var sendtable_ids = data[0]
					if sendtable_ids != null:
						sendtable_ids = PoolIntArray(data[0])
					if can_batch:
						rpc('receive_data_frame', state_id, last_consumed_input_id, sendtable_ids, data[1], csp_property_ids)
						for peer_id2 in multiplayer.get_network_connected_peers():
							if not peer_id2 in _peer_prop_reliable_state_ids:
								_peer_prop_reliable_state_ids[peer_id2] = {}
							for prop in reliable_frame:
								_peer_prop_reliable_state_ids[peer_id2][prop] = state_id
					else:
						rpc_id(peer_id, 'receive_data_frame', state_id, last_consumed_input_id, sendtable_ids, data[1], csp_property_ids)
						if not peer_id in _peer_prop_reliable_state_ids:
							_peer_prop_reliable_state_ids[peer_id] = {}
						for prop in reliable_frame:
							_peer_prop_reliable_state_ids[peer_id][prop] = state_id

		# When data for all peers match, we're done after the first loop iteration
		if can_batch:
			break
	_last_frame_had_data = this_frame_had_data

# Prepare data frame based on how long ago last reliable frame was sent to a peer
func prepare_data_frame(prop_reliable_state_ids:Dictionary, time_depth):

	# Gather protocol preference (reliable/unreliable/auto) from all properties
	# and values to be send.
	var frame_reliable = {}
	var frame_unreliable = {}
	var unassigned = {}
	var current_state_id = -1
	if time_depth:
		current_state_id -= time_depth[0]

	var sendtable = synced_properties.keys()
	for prop in sendtable:
		var property = synced_properties[prop]
		
		match property.shouldsend(prop_reliable_state_ids.get(prop, 0), current_state_id):
			[SyncedProperty.CLIENT_OWNED, ..],\
			[SyncedProperty.DO_NOT_SYNC, ..]:
				pass
			[SyncedProperty.RELIABLE_SYNC, var value]:
				frame_reliable[prop] = value
			[SyncedProperty.UNRELIABLE_SYNC, var value]:
				frame_unreliable[prop] = value
			[SyncedProperty.AUTO_SYNC, var value]:
				unassigned[prop] = value
			null, false:
				pass
			var unknown_shouldsend:
				assert(false, 'SyncedProperty.shouldsend() returned unexpected value %s' % unknown_shouldsend)

	# Append AUTO_SYNC to where needed
	if unassigned.size() > 0:
		if frame_reliable.size() > 0:
			for prop in unassigned:
				frame_reliable[prop] = unassigned[prop]
		else:
			for prop in unassigned:
				frame_unreliable[prop] = unassigned[prop]

	return [sendtable, frame_reliable, frame_unreliable]

# Called via RPC from Server, executes on Clients. Communicates property values.
puppet func receive_data_frame(st_id, last_consumed_input_id, sendtable_ids, values, csp_properties):
	if SyncManager.simulate_network_latency != null:
		var delay = rand_range(SyncManager.simulate_network_latency[0], SyncManager.simulate_network_latency[1])
		yield(get_tree().create_timer(delay), "timeout")
		
	if not last_consumed_input_id or last_consumed_input_id >= SyncManager.seq.last_consumed_input_id:
		_update_prop_csp_netframe(csp_properties)
	_update_prop_csp_tick()
	if last_consumed_input_id and last_consumed_input_id > SyncManager.seq.last_consumed_input_id:
		SyncManager.seq.last_consumed_input_id = last_consumed_input_id

	var frame = parse_data_frame(synced_properties.keys(), sendtable_ids, values)
	for prop in synced_properties:
		var property:SyncedProperty = synced_properties[prop]
		var is_csp = is_client_side_predicted(property)

		if prop in frame:
			property.latest_known_server_value = frame[prop]
			property.latest_known_server_state_id = st_id
			if is_csp:
				if last_consumed_input_id:
					if property.debug_log: print('srv_dt_csp(%s)' % st_id)
					correct_prediction_error(property, last_consumed_input_id, frame[prop])
				else:
					if property.debug_log: print('srv_csp_nocorr(%s)' % st_id)
			else:
				if property.debug_log: print('srv_dt')
				property.write(st_id, frame[prop])
				property.last_compensated_state_id = st_id
		elif property.ready_to_read():
			if is_csp and property.last_compensated_state_id < st_id:
				property.latest_known_server_value = property._get(property.last_compensated_state_id)
				property.latest_known_server_state_id = st_id
				if last_consumed_input_id:
					if property.debug_log: print('srv_no_dt_csp(%s)' % st_id)
					correct_prediction_error(property, last_consumed_input_id, property._get(property.last_compensated_state_id))
				else:
					if property.debug_log: print('srv_no_dt_csp_nocorr')
			elif not is_csp and property.last_state_id < st_id:
				property.latest_known_server_value = property._get(-1)
				property.latest_known_server_state_id = st_id
				if property.debug_log: print('srv_no_dt')
				property.write(st_id, property._get(-1))
				property.last_compensated_state_id = st_id
		
	_last_frame_had_data = frame.size() > 0
	SyncManager.seq.update_received_state_id_and_mtime(st_id, last_consumed_input_id)

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

# Correct client-side prediction made some time ago for an older state
# once known valid server state comes delayed by network.
func correct_prediction_error(property:SyncedProperty, input_id:int, value):
	assert(SyncManager.is_client() and is_client_side_predicted(property))
	
	# state_id during which we locally produced input_id frame
	var st_id = SyncManager.seq.input_id_to_state_id(input_id)
	if not st_id:
		return

	# If prediction error has been compensated at some later state_id already,
	# don't do anything. Or if state_id too long ago in the past.
	if property.last_compensated_state_id >= st_id or not property.contains(st_id):
		return
	if property.debug_log: print('csp_err<-%s(%s>%s)'%[input_id, st_id, property.last_compensated_state_id])
	property.last_compensated_state_id = st_id
	
	# Compare newly confirmed `value` with previous prediction. 
	# Difference is the prediction error.
	var error = property._get(st_id) - value
	
	# Immediately subtract prediction error from all predictions, 
	# starting from state_id up to current best predicted property value.
	for i in range(st_id, property.last_state_id+1):
		property._set(i, property._get(i) - error)

	if property.auto_sync_property:
		_auto_sync_to_parent(property)

func calculate_time_depth():
	return SyncManager.seq.calculate_time_depth(get_position_property()._get(-1))

func rollback(property_name=null):
	var last_valid_state_id
	if SyncManager.is_server():
		var time_depth = calculate_time_depth()[0]
		if time_depth <= 0:
			return
		last_valid_state_id = SyncManager.seq.state_id - time_depth
		if last_valid_state_id < 1:
			last_valid_state_id = 1
	elif SyncManager.is_client():
		last_valid_state_id = SyncManager.seq.interpolation_state_id
	else:
		return

	for prop in (synced_properties if property_name == null else [property_name]):
		var property = synced_properties[prop]
		if property.sync_strategy == SyncedProperty.CLIENT_OWNED:
			continue
		if SyncManager.is_client():
			if not is_client_side_predicted(property):
				property.last_compensated_state_id = last_valid_state_id
			_prop_force_csp_until_input_id[prop] = SyncManager.get_local_peer().input_id + 3
		property.rollback(last_valid_state_id)

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

func synced_property(name:String)->SyncedProperty:
	if not synced_properties:
		return null
	return synced_properties.get(name)

func set_belongs_to_peer_id(peer_id):
	if peer_id != 0 and peer_id == multiplayer.get_network_unique_id():
		peer_id = 0
	if peer_id == belongs_to_peer_id:
		return
	var old_peer_id = belongs_to_peer_id
	belongs_to_peer_id = peer_id
	emit_signal("peer_id_changed", old_peer_id, belongs_to_peer_id)

func _has_no_synced_siblings():
	for node in get_parent().get_children():
		if node is get_script() and node != self:
			return false
	return true

func get_client_owned_values()->Array:
	assert(SyncManager.is_client() and is_local_peer())
	# properties in synced_properties are sorted client-owned last
	var result = []
	var keys = synced_properties.keys()
	for i in range(synced_properties.size() - 1, -1, -1):
		var p:SyncedProperty = synced_properties[keys[i]]
		if p.sync_strategy != SyncedProperty.CLIENT_OWNED:
			break
		if not p.ready_to_read():
			return []
		result.append(p.read(-1))
	return result
	
func set_client_owned_values(values:Array)->void:
	assert(SyncManager.is_server())
	# properties in synced_properties are sorted client-owned last
	var vi = 0
	for i in range(synced_properties.size() - 1, -1, -1):
		var p:SyncedProperty = synced_properties[i]
		if p.sync_strategy != SyncedProperty.CLIENT_OWNED:
			break
		assert(values.size() > vi)
		p.write(SyncManager.seq.state_id, values[vi])
		vi += 1

func _get(prop):
	var p = synced_properties.get(prop)
	if not p:
		return
	if not p.ready_to_read() and p.auto_sync_property != '':
		_auto_sync_from_parent(p)
	assert(p.ready_to_read(), "Attempt to read from %s:%s before any writes happened" % [get_path(), prop])
	if not SyncManager.is_client() or is_client_owned(p):
		return p.read(-1)
	if SyncManager.is_client() and is_client_side_predicted(p):
		return p.read(SyncManager.seq.interpolation_state_id)
	return p.read(SyncManager.seq.interpolation_state_id_frac)

func is_writable(p:SyncedProperty):
	
	# Initial write is always allowed
	if not p.ready_to_read():
		return true

	# Client-owned properties are only writable if belong to local peer
	if p.sync_strategy == SyncedProperty.CLIENT_OWNED:
		if not is_local_peer():
			return false

	# Normal interpolated properties are only writable on Server.
	# Writes to non-client-owned and non-client-side-predicted
	# properties is silently ignored on Client.
	# But we always allow the first initializing write, even on a client.
	if SyncManager.is_client():
		if not is_client_side_predicted(p) and not is_client_owned(p):
			return false

	return true

func _set(prop, value):
	var p = synced_properties.get(prop)
	if not p:
		return
	assert(p.ready_to_write(), "Improperly initialized SyncedProperty %s:%s" % [get_path(), prop])

	if not is_writable(p):
		return true

	if p.debug_log: print('lcl_data(->inp%s)' % SyncManager.get_local_peer().input_id)

	var target_state_id = SyncManager.seq.interpolation_state_id if SyncManager.is_client() else SyncManager.seq.state_id
	
	if p.ready_to_read() and SyncManager.is_server() and is_client_side_predicted(p) and target_state_id >= p.last_rollback_from_state_id:
		# When the property has been recently rolled back, we do a special write mode.
		# Writing two indices at once allows to gradually regain frames lost at rollback.
		assert(p.last_rollback_to_state_id < p.last_rollback_from_state_id)
		assert(p.last_state_id >= p.last_rollback_to_state_id)
		assert(p.last_rollback_from_state_id*2 - p.last_rollback_to_state_id > 0)
		assert(p.last_rollback_from_state_id*2 - p.last_rollback_to_state_id <= p.last_rollback_from_state_id*2 - p.last_rollback_to_state_id)
		target_state_id = int(lerp(
			p.last_rollback_to_state_id, 
			p.last_rollback_from_state_id*2 - p.last_rollback_to_state_id, 
			float(target_state_id - p.last_rollback_from_state_id) /(p.last_rollback_from_state_id - p.last_rollback_to_state_id)
		))
		
		# When server does not write to an interpolated property for some time,
		# the first write should interlpolate over 1 state, not many.
		if p.last_state_id < target_state_id-1:
			p.write(target_state_id-1, p.read(-1))

		# NO_INTERPOLATION mode would otherwise set target_state_id-1 to previous value.
		# Value should change at target_state_id-1 rather than target_state_id.
		if p.missing_state_interpolation == SyncedProperty.NO_INTERPOLATION:
			p.write(target_state_id-1, value)

	assert(not SyncManager.is_client() or not p.ready_to_read() or is_client_side_predicted(p) or is_writable(p))
	p.write(target_state_id, value)

	if p.auto_sync_property != '':
		get_parent().set(p.auto_sync_property, value)

	return true
