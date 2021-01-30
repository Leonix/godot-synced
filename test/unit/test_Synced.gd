extends "res://addons/gut/test.gd"

var prop = null
var synced = null

func test_basic_sb():
	prop = autofree(SyncProperty.new())
	prop.name = 'zzzz'
	synced = autofree(Synced.new())
	synced.add_child(prop)
	synced._ready()
	synced.zzzz = 1234
	assert_eq(1234, synced.zzzz)

func test_frame_pack_parse_basic():
	var frame = {
		zzzz = 1234,
		qqqq = 5678
	}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = Synced.pack_data_frame(sendtable, frame)
	var unpacked_frame = Synced.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())
	for k in frame:
		assert_eq(frame[k], unpacked_frame[k], 'error in key %s' % k)

func test_frame_pack_parse_empty_frame():
	var frame = {}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = Synced.pack_data_frame(sendtable, frame)
	assert_null(packed[0])
	assert_null(packed[1])
	var unpacked_frame = Synced.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())

func test_frame_pack_parse_no_ids():
	var frame = {
		wwww = 1234,
		qqqq = 5678
	}
	var sendtable = ['qqqq', 'wwww', 'zzzz', 'tttt']
	var packed = Synced.pack_data_frame(sendtable, frame)
	assert_null(packed[0])
	var unpacked_frame = Synced.parse_data_frame(sendtable, packed[0], packed[1])
	assert_true(unpacked_frame is Dictionary)
	assert_eq(frame.size(), unpacked_frame.size())
	for k in frame:
		assert_eq(frame[k], unpacked_frame[k], 'error in key %s' % k)
