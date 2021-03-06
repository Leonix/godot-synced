extends Reference
class_name SyncSequence

# Server: last World State that's been processed (or being processed)
# Client: an artifical value designed to match state_id of a netframe when
# the new netframe comes from the server. It increments every physics tick but
# can sometimes skip states or hold for one value for several ticks 
# in order to achieve time sync.
var state_id: int = 1

# Same as state_id, smoothed out into float during _process() calls
var state_id_frac: float setget , get_state_id_frac

# Client: same as state_id but takes interpolation lag into account
var interpolation_state_id: int setget ,get_interpolation_state_id

# Client: same as state_id_frac but takes interpolation lag into account
var interpolation_state_id_frac: float setget ,get_interpolation_state_id_frac

# Last input_id generated by local player, processed by server.
var last_consumed_input_id = 0

var current_latency_in_state_ids = 0

var _mgr # :SyncManager
var _input_id_to_state_id: SyncPeer.CircularBuffer

func _init(manager):
	_mgr = manager
	_input_id_to_state_id = SyncPeer.CircularBuffer.new(
		int(max(
			_mgr.client_interpolation_history_size, 
			_mgr.input_frames_history_size
		)), 
		0
	)

# Called by SyncManager at _process() time
func _process(_delta):
	_fix_state_id_frac()

# Called by SyncManager at _physics_process() time
func _physics_process(_delta):
	_first_process_since_physics_process = true

	# Increment global state time
	state_id += 1
	# Fix clock desync
	if _mgr.is_client():
		state_id = _fix_current_state_id(state_id)
		_input_id_to_state_id.write(_mgr.get_local_peer().input_id, get_interpolation_state_id())

	if _mgr.is_server():
		_input_id_to_state_id.write(_mgr.get_local_peer().input_id, state_id)
		last_consumed_input_id = _mgr.get_local_peer().input_id

func get_time_depth(target_coord):
	return calculate_time_depth(target_coord)[0]

func calculate_time_depth(target_coord):
	if not _mgr.is_server():
		return [0, null]
	# For each peer_id, find the closest object to target_coord
	var candidates = {}
	for wr in _synced_belong_to_players:
		var synced = wr.get_ref()
		if not synced:
			continue
		assert(synced is Synced and synced.belongs_to_peer_id != null)
		var coord = _mgr.get_coord(synced.get_parent())
		if (coord is Vector3) != (target_coord is Vector3):
			continue
		var distance_squared = target_coord.distance_squared_to(coord)
		if not (synced.belongs_to_peer_id in candidates) or candidates[synced.belongs_to_peer_id][0] > distance_squared:
			candidates[synced.belongs_to_peer_id] = [
				distance_squared,
				synced.belongs_to_peer_id,
			]
	var result = _td_calc(candidates.values())
	return result

# Keep track of all Synced objects belonging to players.
# We'll need their positions in order to calcullate Time Depth.
var _synced_belong_to_players = []
func update_synced_belong_to_players(before, after, synced: Synced):
	if synced.ignore_peer_time_depth:
		return
	if before != null and after == null:
		var new_arr = []
		for wr in _synced_belong_to_players:
			var synced2 = wr.get_ref()
			if synced2 and synced2 != synced:
				new_arr.append(synced2)
		_synced_belong_to_players = new_arr
	elif before == null and after != null:
		_synced_belong_to_players.append(weakref(synced))
		if not synced.synced_property('_td_position'):
			# Need to track positions of stuff that belogs to players
			# in order to calculate Time depth
			if synced.get_parent() is Node2D or synced.get_parent() is Spatial:
				synced.add_synced_property('_td_position', SyncedProperty.new({
					missing_state_interpolation = SyncedProperty.NO_INTERPOLATION,
					interpolation = SyncedProperty.NO_INTERPOLATION,
					sync_strategy = SyncedProperty.DO_NOT_SYNC,
					auto_sync_property = 'translation' if synced.get_parent() is Spatial else 'position'
				}))

func _td_calc(players: Array):
	# No reason to bend spacetime when there's only one player
	if players.size() <= 1:
		return [0, null]

	# we are only interested in two closest players
	players.sort_custom(self, '_td_calc_sorter')
	players = players.slice(0, 1)
	assert(2 == players.size() and players[0][0] <= players[1][0])
	var distance_to_closest_sq = players[0][0]
	var distance_to_second_closest_sq = players[1][0]
	if distance_to_second_closest_sq <= 0:
		return [0, null] # paranoid mode

	# We want time depth at coordinate of each player to be equal to plat player's delay
	# When distance is equal to both players, time depth is 0
	# Far away from either player, time depth is 0
	var closest_peer_id = players[0][1]
	var half_delay = state_id - _mgr.get_peer(closest_peer_id).state_id
	return [
		int(half_delay * (1 - clamp(distance_to_closest_sq / distance_to_second_closest_sq, 0, 1))),
		closest_peer_id
	]
func _td_calc_sorter(a, b):
	return a[0] < b[0]

# Used to sync server clock and client clock.
# Only maintained on Client
var _old_received_state_id = 0
var _last_received_state_id = 0
var _old_received_state_mtime = 0
var _last_received_state_mtime = 0

# Maintain stats to calculate a running average
# for server tickrate over (up to) last 1000 frames
func update_received_state_id_and_mtime(new_server_state_id, consumed_input_id):
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

	if consumed_input_id:
		var old_client_state_id = input_id_to_state_id(consumed_input_id)
		current_latency_in_state_ids = int(move_toward(current_latency_in_state_ids, new_server_state_id - old_client_state_id, 1))

func reset_client_connection_stats():
	_last_received_state_mtime = 0
	_old_received_state_mtime = 0
	_last_received_state_id = 0
	_old_received_state_id = 0
	state_id = 1

# On Client, CSP correction must remember when we recorded each input frame
func input_id_to_state_id(input_id:int):
	assert(_mgr.is_client())
	if not _input_id_to_state_id.contains(input_id):
		return null
	return _input_id_to_state_id.read(input_id)

# Shenanigans needed to calculate state_id_frac
var _state_id_frac_fix = 0.0
var _first_process_since_physics_process = true

# idea behind this is to make first call to _process() after _physics_process()
# always give integer state_id_frac
func _fix_state_id_frac():
	if _first_process_since_physics_process and _mgr.state_id_frac_to_integer_reduction > 0:
		_first_process_since_physics_process = false
		_state_id_frac_fix = move_toward(
			_state_id_frac_fix, 
			Engine.get_physics_interpolation_fraction(), 
			_mgr.state_id_frac_to_integer_reduction
		)

# This scary logic figures out if client should skip some state_ids
# or wait and render state_id two times in a row. This is needed in case
# of clock desync between client and server, or short network failure.
func _fix_current_state_id(st_id:int)->int:
	assert(_mgr.is_client())
	var should_be_current_state_id = int(clamp(st_id, _last_received_state_id, _last_received_state_id + _mgr.client_interpolation_lag))
	if abs(should_be_current_state_id - st_id) > _mgr.client_interpolation_lag + _mgr.max_offline_extrapolation:
		# Instantly jump if difference is too large
		st_id = should_be_current_state_id
	else:
		# Gradually move towards proper value
		st_id = int(move_toward(st_id, should_be_current_state_id, 1))
	# Refuse to extrapolate more than allowed by global settings
	if st_id > _last_received_state_id + _mgr.max_offline_extrapolation:
		st_id = _last_received_state_id + _mgr.max_offline_extrapolation
	return st_id

func get_interpolation_state_id()->int:
	assert(_mgr.is_client())
	var result = state_id - _mgr.client_interpolation_lag
	return result if result > 1 else 1

func get_interpolation_state_id_frac()->float:
	assert(_mgr.is_client())
	return max(1, get_state_id_frac() - _mgr.client_interpolation_lag)

func get_state_id_frac():
	if Engine.is_in_physics_frame():
		return float(state_id)
	var result = Engine.get_physics_interpolation_fraction() - _state_id_frac_fix
	result = clamp(result, 0.0, 0.99)
	return result + state_id
