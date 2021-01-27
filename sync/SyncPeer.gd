extends Node

# Script for SyncPeer.tscn scene.
# Scene holds data structures for one network peer (including local).
# Instanced as children of SyncManager for each network peer, including local.
# SyncPeer with Node.name=='0' always exists on both client and sercer,
# even when no network is initialized, and maps to local peer.
# Remote SyncPeers only exist on server and have Node.name equal to their network_peer_id.
# Remote SyncPeers are added and removed as clients connect and disconnect from server.

# SyncProperty stores a history of input frames from both local peer and remote peers. 
# Each input frame is a Dictionary mapping Input action name:String to value.
var storage: SyncProperty

# Input facade is an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# It unifies for Game Logic reading input from local and remote peers.
onready var facade = $SyncInputFacade

# Last input_id of input frame received from this player via network
var last_input_id = 0

func _init():
	storage = SyncProperty.new({
		max_extrapolation = 0,
		missing_state_interpolation = SyncProperty.NO_INTERPOLATION,
		interpolation = SyncProperty.NO_INTERPOLATION,
		sync_strategy = SyncProperty.DO_NOT_SYNC
	})
	storage.resize(SyncManager.input_frames_history_size)

func _ready():
	if is_local():
		# note that SyncPeers are attached to tree when SyncManager is ready,
		# so calling get_parent() here is ok
		last_input_id = get_parent().input_id
	
func is_local():
	return self.name == '0'
