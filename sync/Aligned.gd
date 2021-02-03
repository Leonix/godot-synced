extends Node
class_name Aligned

#
# Aligned node allows to set up lag compensation technique for efficient continuous
# collision detection or (local, non-ranged) hit-scans every frame.
# Instead of applying and reverting lag compensation on demand every frame,
# this node keeps part of scene tree sort-of lag-compensated at all times.
# 
# Attach this script to a Node2D or a Spatial. `Aligned` keeps changing its Transform
# to make an illusion that children of Aligned are positioned and rotated as if
# being in the past, according to global Time Depth value of parent's position
# relative to all players.
#
# Transform and rotation from this node are only applied on Server.
# `Aligned` does nothing to compendate how clients see the world.
# For cliend-side counterpart, see SyncedProperty.time_depth
#

onready var synced: Synced

# `Aligned` works by adding two SyncedProperties to sibling Synced object.
# These properties are set up to track rotation and position (translation for Spatial)
# and are never actually sent over the network to clients.

func _ready():
	# Make sure we're attached to either Spatial or Node2d
	assert(get_parent() is Spatial or get_parent() is Node2D, "Aligned node's parent must be either a Node2D or a Spatial.")
	if get_parent() is Spatial:
		assert('rotation' in self and 'translation' in self, "Aligned node must be set as script for a Spatial.")
	else:
		assert('rotation' in self and 'position' in self, "Aligned node must be set as script for a Node2D.")
	synced = _get_synced_sibling()
	assert(synced is Synced)

func _physics_process(_d):
	# Only applies while on the server
	if not SyncManager.is_server():
		return

	var rotation_property = synced.get_rotation_property()
	var position_property = synced.get_position_property()

	var old_state_id = get_time_depth_state_id()
	for p in [position_property, rotation_property]:
		var real_value = p._get(SyncManager.state_id)
		var old_value = p._get(old_state_id)
		self.set(p.auto_sync_property, old_value - real_value)
		#print('%s=%s' % [p.auto_sync_property, old_value - real_value])

func get_time_depth_state_id():
	var real_coord = synced.get('position')
	if real_coord == null:
		return SyncManager.state_id
	return SyncManager.state_id - SyncManager.get_time_depth(real_coord)

func _get_synced_sibling():
	for sibling in get_parent().get_children():
		if sibling is Synced:
			return sibling

func _get(prop):
	var p = synced.synced_properties.get(prop) if synced and synced.synced_properties else null
	if not p:
		return null
	if SyncManager.is_client():
		return synced._get(prop)

	if p.sync_strategy == SyncedProperty.CLIENT_OWNED:
		return synced._get(prop)
	#if p.debug_log: print('aligned(%s)%s' % [
	#	get_time_depth_state_id(), 
	#	str(p.read(get_time_depth_state_id())) if p.changed(get_time_depth_state_id()-1) else '--'
	#])
	return p.read(get_time_depth_state_id())

func _set(prop, value):
	var p = synced.synced_properties.get(prop) if synced and synced.synced_properties else null
	if not p:
		return null
	
	assert(p.sync_strategy != SyncedProperty.CLIENT_OWNED, "Must not write to client-owned property via aligned.%s" % prop)
	
	if SyncManager.is_client():
		[value] # !!! TODO
	else:
		pass # !!! TODO
