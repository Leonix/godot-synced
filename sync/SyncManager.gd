extends Node

#
# Sync lib requires this class to be autoloaded as SyncManager singleton.
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

# Last input frame that has been captured and either sent to server (if on client)
# or processed locally (if on server)
var input_id = 1 setget set_input_id, get_input_id

# Last World State id that has been captured.
var state_id = 1 setget set_state_id, get_state_id

# Last World State id that has been captured.
var state_id_frac setget , get_state_id_frac

# Shenanigans needed to calculate state_id_frac
var _prev_process_delta = 0.0
var _time_since_last_physics_process = 0.0

func _process(delta):
	# _process() on autoloaded nodes gets called before rest of the scene tree.
	# Idea is: first _process() after _physics_process(delta) always has integer state_id.
	_time_since_last_physics_process += _prev_process_delta
	_prev_process_delta = delta

func _physics_process(_delta):
	_time_since_last_physics_process = 0.0
	_prev_process_delta = 0.0
	input_id += 1
	state_id += 1

# Game code call this on server for each client connected, or on client when connected to server
func client_connected():
	pass # !!! todo

func set_input_id(_value):
	pass # read-only

func get_input_id():
	return input_id

func set_state_id(_value):
	pass # read-only

func get_state_id():
	return input_id

func get_state_id_frac():
	var result = _time_since_last_physics_process / get_physics_process_delta_time()
	if result >= 1.0:
		result = 0.99
	return result + state_id

# Instantiated instances of SyncBase report here upon creation
func SyncBase_created(sb, spawner=null):
	pass # !!!
