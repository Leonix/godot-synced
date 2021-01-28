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

var sync_properties = {}

func _ready():
	SyncManager.SyncBase_created(self, spawner)
	for property in get_children():
		assert(property is SyncProperty, 'All childrn of SyncBase must be SyncProperty (looking at you, %s)' % property.get_path())
		if not property.ready_to_write():
			SyncManager.init_sync_property(property)
			sync_properties[property.name] = property

func get_input():
	if not input or input.get_peer_id() != belongs_to_peer_id:
		input = SyncManager.get_input_facade(belongs_to_peer_id)
	return input

func is_local_peer():
	return belongs_to_peer_id == 0

func default_read_state_id():
	return SyncManager.state_id

func default_write_state_id():
	return SyncManager.state_id

func _get(prop):
	var p = sync_properties.get(prop)
	if p:
		assert(p.ready_to_read(), "Attempt to read from %s:%s before any writes happened" % [get_path(), prop])
		return p.read(default_read_state_id())

func _set(prop, value):
	var p = get_node(prop)
	if p:
		assert(p.ready_to_write(), "Improperly initialized SyncProperty %s:%s" % [get_path(), prop])
		p.write(default_write_state_id(), value)
		return true
