#
# Stores history of values of a single property of a Synced over a period
# of consecutive integer state_ids.
# Allows to interpolate in between stored values, as well as extrapolate
# for some time into the future.
#

extends Node
class_name SyncedProperty

# Possible property sync strategies (`options.sync_strategy`)
enum { 
	# Never sent to Clients. Not readable on Clients.
	# Server still records history of values.
	# Useful for server-side lag compensation.
	DO_NOT_SYNC, 
	
	# Send to clients via reliable channel when value changes.
	# Great for stuff that changes rarely.
	RELIABLE_SYNC,
	
	# Send to clients every frame. Never gets merged into reliable frame,
	# always forces separate unreliable frame.
	# Great for stuff that changes often and needs fast updates.
	UNRELIABLE_SYNC,
	
	# Remember per-player last frame (state_id) that was sent to player via reliable channel.
	# Also remember which state_id value of the property changed last time.
	# If value did not send since last reliable frame, do not send. 
	# If value changed since last reliable frame, but did not change during last
	# `options.strat_stale_delay` frames, then force update via reliable channel. 
	# Otherwise (when value changed since last reliable frame, but property changed
	# recently enough not to be considered stale) then prefer reliable channel 
	# if some other property forced reliable, and agree for unreliable when all
	# other properties use unreliable.
	AUTO_SYNC,
	
	# Do not sent values of this property from Server to Client.
	# Client sends these as part of their Input Frames.
	CLIENT_OWNED
}

# See possible sync strategies in Enum above
export(int, 'DO_NOT_SYNC', 'RELIABLE_SYNC', 'UNRELIABLE_SYNC', 'AUTO_SYNC', 'CLIENT_OWNED') var sync_strategy = AUTO_SYNC

# See AUTO_SYNC in enum above
export var strat_stale_delay = 9

# Possible interpolation strategies
enum {
	# Use leftmost known value as interpolation result
	NO_INTERPOLATION,
	# Interpolate between left and right value linearly
	LINEAR_INTERPOLATION
}
# Interpolattion strategy to use in between two neighboring int state_ids
export(int, 'NO_INTERPOLATION', 'LINEAR_INTERPOLATION') var interpolation = NO_INTERPOLATION
# Interpolattion strategy to calculate missing value for int state_id,
# using two other int state_ids that are far apart.
export(int, 'NO_INTERPOLATION', 'LINEAR_INTERPOLATION') var missing_state_interpolation = NO_INTERPOLATION
# no more than this numebr of state_ids are allowed to extrapolate
# when state_id requested from the future
export var max_extrapolation = 15

# possible client-side-prediction strategies
enum {
	# Client-Side Prediction is disabled
	NO_CSP,
	
	# Only enable CSP if Synced belongs to local peer
	IF_BELONGS_TO_LOCAL_PEER_CSP,
	
	# Always enable Client-Side-Prediction
	ALWAYS_CSP
}
# Allow client-side predicted values for this property
export(int, 'NO_CSP', 'IF_BELONGS_TO_LOCAL_PEER_CSP', 'ALWAYS_CSP') var client_side_prediction = NO_CSP

# Array-like storage place for historic values.
# This is used as a circular buffer. We keep track of last written index self.last_index,
# and loop over when reach the end of allocated container space.
# Contains consecutive values for all integer state_ids ending with self.last_state_id
# The earliest value we know is always at `self.last_index+1` (possibly loop over),
# and the earliest value always corresponds to `self.last_state_id - container.size() + 1`
var container: Array
# Index in self.container that contains data for the most recent state_id
# -1 here means the property has never been written to yet.
var last_index: int = -1
# state_id written at container[last_index]
var last_state_id: int = 0
# state_id when value changed latst time
var last_changed_state_id: int = 0
# Last time Synced applied CSP compensation based on data that came from server
var last_compensated_state_id: int = 0
# Prints all successfull writes to this to console
export var debug_log = false
# When set, Synced will write to this SyncedProperty after each _physics_process()
# and _process() on Server, taking data from proeprty with given name on Synced parent;
# and will read from it before each _physics_process() and _process() on Client,
# writing to corresponding property on parent node of Synced.
# Basically this directly syncs given property on Synced parent node.
# Useful for `position` and such.
export var auto_sync_property = ''
# Storage for additional meta-data.
# Unrecognized options passed to the constructor go here.
export var meta: Dictionary

func _init(options: Dictionary = {}):
	meta = {}
	container = []
	for k in options:
		if is_valid_option(k):
			self.set(k, options[k])
		else:
			meta[k] = options[k]

func _get(state_id_str):
	if state_id_str is int and state_id_str <= last_state_id:
		assert(ready_to_read(), "Attempt to read from SyncedProperty before any write has happened.")
		return self.container[_get_index(relative_state_id(state_id_str))]
	var state_id = float(state_id_str)
	if state_id != 0.0:
		return self.read(state_id)

# Return value from last state_id. Optionally allows to skip several last state ids,
# e.g. last(1) will return second last.
func last(skip=0):
	return self.read(max(1, last_state_id - skip))

func _set(state_id_str, value):
	var state_id = int(state_id_str)
	if state_id != 0:
		self.write(state_id, value)
		return true

# Returns property value at given state_id, doing all the interpolation 
# and extrapolation magic as set up for this property.
func read(state_id: float):
	assert(ready_to_read(), "Attempt to read from SyncedProperty before any write has happened.")

	if state_id < 0:
		state_id = max(1, last_state_id + 1 + state_id)
	if last_state_id < state_id:
		return _extrapolate(state_id)
	# state_ids and container indices we need to interpolate between
	var left_state_id = int(state_id)
	var right_state_id = left_state_id + 1
	var left_index = _get_index(left_state_id)
	var right_index = _get_index(right_state_id)
	
	# if we're asked for past long gone, return last we know
	if left_index == right_index:
		return container[left_index]
	
	# interpolate between two known historic values
	return _interpolate(
		self.interpolation,
		left_state_id,
		container[left_index],
		right_state_id,
		container[right_index],
		state_id
	)

# Write property value at given state_id.
# Overwrites historic value or adds a new state_id.
# Write is ignored if state_id is too old.
func write(state_id: int, value):
	assert(ready_to_write(), "Attempt to write to SyncedProperty before container size is set.")
	if debug_log:
		print('%s[%d]=%s' % [name, state_id, value])
	# Initial write must fill in the whole buffer
	if last_index < 0:
		last_index = 0
		last_state_id = state_id
		last_changed_state_id = last_state_id
		for i in range(container.size()):
			container[i] = value
		return
	
	# write to past long gone is silently ignored
	if state_id < last_state_id - container.size() + 1:
		return

	# Overwrite historic value from the not-so-long-ago
	if state_id <= last_state_id:
		container[_get_index(state_id)] = value
		if last_changed_state_id < state_id and container[_get_index(state_id-1)] != value:
			last_changed_state_id = state_id
		return

	var new_last_state_id = state_id
	var old_last_state_id = last_state_id
	var old_last_value = container[last_index]

	# Fill in values we have skipped between old_last_state_id and new_last_state_id.
	# This maintains that container is tightly packed and no state_id is missing a place.

	# Loop starting from self.last_index+1 up to (wrappig over) self.last_index-1
	# for how many iterations are needed. (Leave space for last value itself).
	var loop_iterations_count = new_last_state_id - old_last_state_id - 1
	# Loop iteration count can not exceed size of container
	loop_iterations_count = clamp(loop_iterations_count, 0, container.size()-1)

	for i in range(loop_iterations_count):
		last_index = wrapi(last_index + 1, 0, container.size())
		container[last_index] = _interpolate(
			missing_state_interpolation, 
			old_last_state_id, 
			old_last_value, 
			new_last_state_id,
			value,
			new_last_state_id - loop_iterations_count + i
		)

	# Finally, write the new_last_state_id value
	last_state_id = new_last_state_id
	last_index = wrapi(last_index + 1, 0, container.size())
	container[last_index] = value

	if old_last_value != value:
		last_changed_state_id = new_last_state_id
	
# Extrapolate according to settings of this propoerty, based on two given data points
func _extrapolate(state_id):
	# Not allowed to exxtrapolate past certain point
	if last_state_id + max_extrapolation < state_id:
		state_id = last_state_id + max_extrapolation

	# floor state_id to closest integer in order to simulate interpolated behaviour
	# of interpolation=NO_INTERPOLATION, missing_state_interpolation=LINEAR_INTERPOLATION
	if self.interpolation != LINEAR_INTERPOLATION:
		assert(self.interpolation == NO_INTERPOLATION, 'SyncedProperty interpolation strategy not implemented for extrapolation %s' % self.interpolation)
		state_id = int(state_id)

	return _interpolate(
		self.missing_state_interpolation,
		last_state_id - 1,
		container[wrapi(last_index-1, 0, container.size())], 
		last_state_id,
		container[last_index], 
		state_id
	)

# Interpolate according to given strategy, based on two given data points.
# Note that state_id is not always between left_state_id and right_state_id
# because this same function is used during extrapolation, too.
static func _interpolate(strategy, left_state_id:int, left_value, right_state_id:int, right_value, state_id:float):
	if strategy == NO_INTERPOLATION:
		if state_id < right_state_id:
			return left_value
		else:
			return right_value
			
	assert(strategy == LINEAR_INTERPOLATION, 'Unknown SyncedProperty interpolation strategy %s' % strategy)
	return lerp(
		left_value, 
		right_value, 
		lerpnorm(left_state_id, right_state_id, state_id)
	)

# Closest index to given state_id.
func _get_index(state_id: int)->int:
	state_id = int(clamp(state_id, last_state_id - container.size() + 1, last_state_id))
	return wrapi(last_index - last_state_id + state_id, 0, container.size())

# Whether property contains value for given state_id
func contains(state_id: int):
	return state_id == int(clamp(state_id, last_state_id - container.size() + 1, last_state_id))

# helper to normalize into proper range the third argument for lerp()
static func lerpnorm(left: float, right: float, middle: float)->float:
	assert(right > left)
	return (middle - left) / (right - left)

# Synced must specify buffer size for each property depending on client/server state
# and other property settings
func resize(new_size):
	assert(last_index < 0, "Attempt to resize a non-empty SyncedProperty")
	container.resize(new_size)

# Determine value to be sent and protocol preference
func shouldsend(last_reliable_state_id:int, current_state_id:int=-1):
	if self.sync_strategy == DO_NOT_SYNC or not ready_to_read():
		return null
	last_reliable_state_id = relative_state_id(last_reliable_state_id)
	current_state_id = relative_state_id(current_state_id)
	if not changed(last_reliable_state_id, current_state_id):
		return null
	# When property stops changing, AUTO_SYNC becomes RELIABLE_SYNC
	if self.sync_strategy == AUTO_SYNC and current_state_id - last_changed_state_id > strat_stale_delay:
		return [RELIABLE_SYNC, _get(current_state_id)]
	return [self.sync_strategy, _get(current_state_id)]

# Return true if property changed between these two states
# (or since given state if only one is provided)
func changed(old_state_id:int, new_state_id:int=-1):
	if old_state_id == 0:
		return true
	old_state_id = relative_state_id(old_state_id)
	new_state_id = relative_state_id(new_state_id)
	if old_state_id >= new_state_id or last_changed_state_id <= old_state_id and last_changed_state_id <= new_state_id:
		return false
	if old_state_id < last_changed_state_id and last_changed_state_id <= new_state_id:
		return true
	# Strictly speaking, this is wrong because value may have changed somewhere
	# and then returned back again. I'll keep it like that until there's 
	# a strong reason to be 100% precise.
	return _get(old_state_id) != _get(new_state_id)

# helper to normalize negative indices
func relative_state_id(state_id:int)->int:
	if state_id < 0:
		var result = last_state_id + 1 + state_id
		return result if result > 0 else 1
	return state_id

func ready_to_read():
	return last_index >= 0

func ready_to_write():
	return container.size() > 0

static func is_valid_option(name):
	match name:
		'sync_strategy', 'strat_stale_delay', 'interpolation', \
		'missing_state_interpolation', 'max_extrapolation', 'container':
			return true
	return false
