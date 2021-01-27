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
var state_id_frac_fix = 0.0
var first_process_since_physics_process = true

# SyncInput needs RPC so it must be inside the tree
var _input = preload('SyncInput.gd').new()

func _ready():
	self.add_child(_input)

func _process(_delta):
	
	# Idea is: first call to _process() after _physics_process(delta) 
	# should see integer state_id_frac. But we don't want to interfere
	# too much with regularity of state_id_frac. 0.04 seems to work fine.
	if first_process_since_physics_process:
		state_id_frac_fix = move_toward(state_id_frac_fix, Engine.get_physics_interpolation_fraction(), 0.04)
		first_process_since_physics_process = false

func _physics_process(_delta):
	# Server: send previous World State to clients
	# !!!
	
	# Increment global state time
	first_process_since_physics_process = true
	input_id += 1
	state_id += 1
	
	# Server: update Client-owned properties of all SyncBase objects, 
	# taking them from new input_id
	# !!!
	
	# Build new Input frame
	# !!!
	
	# Client: send input frames to server if time has come
	# !!!

# Game code calls this
# - on server for each client connected, 
# - on client when connected to server
func client_connected():
	pass # !!! todo

# Game code calls this 
# - on server when existing client disconnects, 
# - on client when disconnected from server
func client_disconnected():
	pass # !!! todo

# Input facade to read player's input through
func get_input(peer=null):
	pass # !!! todo

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
