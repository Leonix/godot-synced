#
# !!! Property setting to update corresponding property on parent node
# every _process() and _physics_process()
# * will probably have to use crazy stuff like _process_internal()
#

extends Node
class_name SyncBase

# Network peer whose Input commands this object listens to.
# Game logic should set this to appropriate peer_id for objects
# that are normally would read input from Input class or use _input() callback
# 0 here always means local player. null means no one (dummy input).
var belongs_to_peer_id = null

# Should be set by whoever instanced scene containing this before attaching to scene tree.
# Affects how Client-Side-Predicted new entities locate their Server counterparts.
var spawner: SyncBase = null # !!! not implemented, why is it here...

# Input facade to read player's input through instead of builtin Input
var input setget ,get_input

func _ready():
	SyncManager.SyncBase_created(self, spawner)

func get_input():
	if not input or input.get_peer_id() != belongs_to_peer_id:
		input = SyncManager.get_input_facade(belongs_to_peer_id)
	return input

func is_local_peer():
	return belongs_to_peer_id == 0
