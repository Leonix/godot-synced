extends Node
class_name TimeDepth

#
# TimeDepth node allows to set up lag compensation technique for efficient continuous
# collision detection or (local, non-ranged) hit-scans every frame.
# Instead of applying and reverting lag compensation on demand every frame,
# this node keeps part of scene tree sort-of lag-compensated at all times.
# 
# Attach this script to a Node2D or a Spatial. TimeDepth keeps changing its Transform
# to make an illusion that children of TimeDepth are positioned and rotated as if
# being in the past, according to global Time Depth value of parent's position
# relative to all players.
#
# Transform and rotation from this node are only applied on Server.
# TimeDepth does nothing to compendate how clients see the world.
# For cliend-side counterpart, see SyncedProperty.time_depth
#

onready var synced: Synced

# TimeDepth works by adding two SyncedProperties to sibling Synced object.
# These properties are set up to track rotation and position (translation for Spatial)
# and are never actually sent over the network to clients.
var rotation_property: SyncedProperty
var position_property: SyncedProperty

func _ready():
	# Make sure we're attached to either Spatial or Node2d
	assert('rotation' in self and ('translation' in self or 'position' in self))
	
	synced = _get_synced_sibling()
	assert(synced is Synced)

	position_property = synced.synced_property('_td_position')
	if position_property:
		assert(rotation_property.auto_sync_property == ('translation' if 'translation' in self else 'position'))
	else:
		position_property = synced.add_synced_property('_td_position', SyncedProperty.new({
			missing_state_interpolation = SyncedProperty.NO_INTERPOLATION,
			interpolation = SyncedProperty.NO_INTERPOLATION,
			sync_strategy = SyncedProperty.DO_NOT_SYNC,
			auto_sync_property = 'translation' if 'translation' in self else 'position'
		}))

	rotation_property = synced.synced_property('_td_rotation')
	if rotation_property:
		assert(rotation_property.auto_sync_property == 'rotation')
	else:
		rotation_property = synced.add_synced_property('_td_rotation', SyncedProperty.new({
			missing_state_interpolation = SyncedProperty.NO_INTERPOLATION,
			interpolation = SyncedProperty.NO_INTERPOLATION,
			sync_strategy = SyncedProperty.DO_NOT_SYNC,
			auto_sync_property = 'rotation'
		}))

func _physics_process(_d):
	# Only applies while on the server
	if not SyncManager.is_server():
		return

	if not position_property.ready_to_read() or not rotation_property.ready_to_read():
		return

	var real_coord = SyncManager.get_coord(get_parent())
	assert(real_coord != null)
	var old_state_id = SyncManager.state_id - SyncManager.get_time_depth(real_coord)
	for p in [position_property, rotation_property]:
		var real_value = p._get(SyncManager.state_id)
		var old_value = p._get(old_state_id)
		self.set(p.auto_sync_property, old_value - real_value)
		#print('%s=%s' % [p.auto_sync_property, old_value - real_value])

func _get_synced_sibling():
	for sibling in get_parent().get_children():
		if sibling is Synced:
			return sibling
