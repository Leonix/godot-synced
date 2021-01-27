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
var storage = SyncProperty.new({
	max_extrapolation = 0,
	missing_state_interpolation = SyncProperty.NO_INTERPOLATION,
	interpolation = SyncProperty.NO_INTERPOLATION,
	sync_strategy = SyncProperty.DO_NOT_SYNC
})

# Input facade is an object to read player's input through,
# like a (limited) drop-in replacement of Godot's Input class.
# It unifies for Game Logic reading input from local and remote peers.
onready var facade = $SyncInputFacade

# Local peer on both client and server: last input frame that has been captured.
# Remote peer on server: last input frame that has been processed from this peer
# (or is being processed if we're in _physics_processs())
# input_id gets incremented by one each _physics_process() step.
# This is used by InputFacade to consume input from peers at the same rate 
# they generate it.
var input_id = 1

func _init():
	storage.resize(SyncManager.input_frames_history_size)

func _physics_process(_delay):
	input_id += 1
	
	if not is_local():
		# Skip input frames if too many comes from the client for any reason.
		# Simple strategy: skip all input frames we have lost data for.
		# Short storage buffer size will keep clients from large input lag.
		# !!! Skipping random frames has a major downside that server may miss
		# an occasional just_pressed or just_released
		if input_id <= storage.last_state_id - storage.container.size():
			input_id = 1 + storage.last_state_id - storage.container.size()

		# TODO: it is possible to invent more complicated srategies, like skipping 
		# current frame if it matches either previous or the next one...
		# At this point it feels premature to try that.

func is_local():
	return self.name == '0'
