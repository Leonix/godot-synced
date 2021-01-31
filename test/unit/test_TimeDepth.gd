extends "res://addons/gut/test.gd"

var TimeDepthReference = preload("res://sync/TimeDepth.gd")

func test_basic_td_node2d():
	var node = autofree(Node2D.new())
	var synced = autofree(Synced.new())
	var td = autofree(Node2D.new())
	td.set_script(TimeDepthReference)
	node.add_child(synced)
	node.add_child(td)
	add_child_autofree(node)
	assert_eq(2, synced.get_child_count())
	assert_not_null(synced.synced_property('_td_position'))
	assert_not_null(synced.synced_property('_td_rotation'))
	assert_false(synced._should_auto_update_parent)
	assert_true(synced._should_auto_read_parent)

func test_basic_td_spatial():
	var node = autofree(Spatial.new())
	var synced = autofree(Synced.new())
	var td = autofree(Spatial.new())
	td.set_script(TimeDepthReference)
	node.add_child(td)
	node.add_child(synced)
	add_child_autofree(node)
	assert_eq(2, synced.get_child_count())
	assert_not_null(synced.synced_property('_td_position'))
	assert_not_null(synced.synced_property('_td_rotation'))
	assert_false(synced._should_auto_update_parent)
	assert_true(synced._should_auto_read_parent)
