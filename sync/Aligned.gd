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
	synced.is_csp_enabled = true

func _process(_d):
	if not SyncManager.is_server() and not SyncManager.is_client():
		return

	var rotation_property = synced.get_rotation_property()
	var position_property = synced.get_position_property()

	_set_parent = true
	var old_state_id = get_time_depth_state_id()
	for p in [position_property, rotation_property]:
		if not p.ready_to_read():
			continue
		var real_value
		var old_value
		if SyncManager.is_server():
			# On server, we show visuals as if back in time according to Time Depth.
			real_value = p._get(-1)
			old_value = p._get(old_state_id)
		elif synced.is_client_side_predicted(p) and p.last_rollback_from_state_id > 0:
			# On client, we show predicted coordinates slightly back in time
			var target_state_id = SyncManager.seq.interpolation_state_id_frac
			real_value = p._get(int(target_state_id))
			old_state_id = target_state_id - synced.get_csp_lag(p)
			old_value = p._get(old_state_id)
			if false and get_parent().name == 'Ball' and p.name == 'position': # !!!
				print("%s@%s(%s|%s)=%s(%s)" % [
					p.name, 
					int(target_state_id) % 1000, 
					int(old_state_id) % 1000,
					int(target_state_id) - int(old_state_id),
					int(real_value.x),
					int(old_value.x)
				])
				if false: print([int(p.last_state_id) % 1000, # !!!
					int(p._get(-1).x),
					int(p._get(-2).x),
					int(p._get(-3).x),
					int(p._get(-4).x),
					int(p._get(-5).x),
					int(p._get(-6).x),
					int(p._get(-7).x),
					int(p._get(-8).x),
					int(p._get(-9).x),
					int(p._get(-10).x),
				])
		else:
			if false and get_parent().name == 'Ball' and p.name == 'position': # !!!
				print("Aligned reset")
			real_value = p._get(-1)
			old_value = real_value

		set(p.auto_sync_property, old_value - real_value)
	_set_parent = false

var _set_parent = false

func get_time_depth_state_id():
	if not SyncManager.is_server():
		return 0 # not applicable, not used on clients
	var real_coord = synced.get('position')
	if real_coord == null:
		return SyncManager.seq.state_id
	return SyncManager.seq.state_id - SyncManager.seq.get_time_depth(real_coord)

func _get_synced_sibling():
	for sibling in get_parent().get_children():
		if sibling is Synced:
			return sibling

func touch(prop):
	_set(prop, _get(prop))

func _get(prop):
	var p = synced.synced_properties.get(prop) if synced and synced.synced_properties else null
	if not p:
		return null
	if not SyncManager.is_server() or synced.is_client_owned(p) or not p.ready_to_read():
		return synced._get(prop)
	return p.read(get_time_depth_state_id())

func _set(prop, value):
	if _set_parent:
		return
	var p = synced.synced_properties.get(prop) if synced and synced.synced_properties else null
	if not p:
		return null
	
	if not synced.is_client_owned(p):
		synced.rollback(prop)
	synced._set(prop, value)
	return true
