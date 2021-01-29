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

func test_frame_pack_parse_basic():
	var frame = {
		zzzz = 1234,
		qqqq = 5678
	}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = SyncBase.pack_data_frame(sendtable, frame)
	var unpacked_frame = SyncBase.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())
	for k in frame:
		assert_eq(frame[k], unpacked_frame[k], 'error in key %s' % k)

func test_frame_pack_parse_empty_frame():
	var frame = {}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = SyncBase.pack_data_frame(sendtable, frame)
	assert_null(packed[0])
	assert_null(packed[1])
	var unpacked_frame = SyncBase.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())

func test_frame_pack_parse_no_ids():
	var frame = {
		wwww = 1234,
		qqqq = 5678
	}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = SyncBase.pack_data_frame(sendtable, frame)
	assert_null(packed[0])
	var unpacked_frame = SyncBase.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())
	for k in frame:
		assert_eq(frame[k], unpacked_frame[k], 'error in key %s' % k)
