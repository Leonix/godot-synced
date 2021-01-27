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

# Last input frame that has been captured and either sent to server (if on client)
# or processed locally (if on server)
var input_id = 1 setget set_input_id, get_input_id

# Last World State id that has been captured.
var state_id = 1 setget set_state_id, get_state_id

# Last World State id that has been captured.
var state_id_frac setget , get_state_id_frac

# Shenanigans needed to calculate state_id_frac
var state_id_frac_fix = 0.0
var first_process_since_physics_process = true

# SyncInput needs RPC so it must be inside the tree
var _input = SyncInput.new()

var _mtime_last_input_batch_sent = 0.0

func _ready():
	self.add_child(_input)

func _process(_delta):
	
	# Idea is: first call to _process() after _physics_process(delta) 
	# should see integer state_id_frac. But we don't want to interfere
	# too much with regularity of state_id_frac. 0.04 seems to work fine.
	# !!! TODO make it an editor option...  make many editor options X_x
	if first_process_since_physics_process:
		state_id_frac_fix = move_toward(state_id_frac_fix, Engine.get_physics_interpolation_fraction(), 0.04)
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
	_input.sample(state_id, input_id)

	# Server: update Client-owned properties of all SyncBase objects, 
	# taking them from new input frame from each client
	if is_server():
		pass # !!!
	
	# Client: send input frames to server if time has come
	if is_client():
		var time = OS.get_system_time_msecs()
		if (time - _mtime_last_input_batch_sent) * input_sendrate >= 1.0:
			_mtime_last_input_batch_sent = time
			_input.send_batch()

# Game code calls this
# - on server for each client connected, 
# - on client when connected to server
func client_connected():
	if is_server():
		_input.update_peers(get_tree().multiplayer.get_network_connected_peers())

# Game code calls this 
# - on server when existing client disconnects, 
# - on client when disconnected from server
func client_disconnected():
	if is_server():
		_input.update_peers(get_tree().multiplayer.get_network_connected_peers())

# Input facade to read player's input through. 
# 0 means local player, as well as get_tree().multiplayer.get_network_unique_id()
func get_input(peer_unique_id=0):
	return _input.get_facade(peer_unique_id)

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
