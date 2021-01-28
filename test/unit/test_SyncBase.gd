extends "res://addons/gut/test.gd"

var prop = null
var base = null

func after_each():
	if prop:
		prop.free()
		prop = null
	if base:
		base.free()
		base = null

func test_basic_sb():
	prop = SyncProperty.new()
	prop.name = 'zzzz'
	base = SyncBase.new()
	base.add_child(prop)
	base._ready()
	base.zzzz = 1234
	assert_eq(1234, base.zzzz)
