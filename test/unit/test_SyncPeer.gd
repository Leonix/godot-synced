extends "res://addons/gut/test.gd"

var obj = null

var sendtable1 = {
	'bool': ['bool_zzzz', 'bool_qqqq'],
	'float': ['float_z', 'float_q']
}
var sendtable2 = {
	'bool': [],
	'float': ['float_z']
}
var sendtable3 = {
	'bool': ['bool_zzzz'],
	'float': []
}

var __input_frames_min_batch

func before_all():
	__input_frames_min_batch = SyncManager.input_frames_min_batch
	
func before_each():
	obj = autofree(SyncPeer.new())

func after_each():
	SyncManager.input_frames_min_batch = __input_frames_min_batch

func test_frame_batcher_parser1():
	var frames = [{
		'bool_qqqq': 0,
		'bool_zzzz': 1,
		'float_q': 100.5,
		'float_z': 0.0,
	}, {
		'bool_qqqq': 0,
		'bool_zzzz': 0,
		'float_q': 0.0,
		'float_z': 0.0,
	}]
	var packed_batch = obj.pack_input_batch(sendtable1, frames)
	var frames_out = obj.parse_input_batch(sendtable1, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser2():
	var frames = [{
		'bool_qqqq': 0,
		'bool_zzzz': 0,
		'float_q': 0.0,
		'float_z': 0.0,
	}, {
		'bool_qqqq': 0,
		'bool_zzzz': 0,
		'float_q': 0.0,
		'float_z': 0.0,
	}]
	SyncManager.input_frames_min_batch = frames.size()
	var packed_batch = obj.pack_input_batch(sendtable1, frames)
	assert_eq([], packed_batch[2])
	var frames_out = obj.parse_input_batch(sendtable1, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser3():
	var frames = [{
		'float_z': 1.0,
	}, {
		'float_z': 2.0,
	}, {
		'float_z': 0.0,
	}]
	var packed_batch = obj.pack_input_batch(sendtable2, frames)
	var frames_out = obj.parse_input_batch(sendtable2, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser4():
	var frames = [{
		'bool_zzzz': 1,
	}, {
		'bool_zzzz': 1,
	}, {
		'bool_zzzz': 0,
	}]
	var packed_batch = obj.pack_input_batch(sendtable3, frames)
	var frames_out = obj.parse_input_batch(sendtable3, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser5():
	var frames = [{
		'float_z': 0.0,
	}, {
		'float_z': 0.0,
	}, {
		'float_z': 0.0,
	}]
	SyncManager.input_frames_min_batch = frames.size()
	var packed_batch = obj.pack_input_batch(sendtable2, frames)
	var frames_out = obj.parse_input_batch(sendtable2, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser6():
	var frames = [{
		'bool_zzzz': 0,
	}, {
		'bool_zzzz': 0,
	}, {
		'bool_zzzz': 0,
	}]
	SyncManager.input_frames_min_batch = frames.size()
	var packed_batch = obj.pack_input_batch(sendtable3, frames)
	var frames_out = obj.parse_input_batch(sendtable3, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_frame_batcher_parser7():
	var frames = [{
		'bool_qqqq': 0,
		'bool_zzzz': 1,
		'float_q': 100.5,
		'float_z': 0.0,
		'cop__Player1': [1, 2.0, 3],
	}, {
		'bool_qqqq': 0,
		'bool_zzzz': 0,
		'float_q': 0.0,
		'float_z': 0.0,
		'cop__Player2': [3, 5.0, 9],
	}]
	var packed_batch = obj.pack_input_batch(sendtable1, frames)
	assert_true(packed_batch[1].size() > 0)
	var frames_out = obj.parse_input_batch(sendtable1, packed_batch[0], packed_batch[1], packed_batch[2])
	assert_eq_deep(frames, frames_out)

func test_cb_get_index():
	var prop = SyncPeer.CircularBuffer.new(4, 0)
	assert_true(prop is Reference)
	prop.write(11, 111.0)
	prop.write(12, 112.0)
	prop.write(13, 113.0)
	prop.write(14, 114.0)
	prop.write(15, 115.0)
	assert_eq(15, prop.last_input_id)
	assert_eq(112.0, prop.container[prop._get_index(11)])
	assert_eq(115.0, prop.container[prop._get_index(16)])
	for i in range(12, 16):
		assert_eq(100.0+i, prop.container[prop._get_index(i)])

func test_cb_fetch():
	var prop = SyncPeer.CircularBuffer.new(10, 0.0)
	assert_true(prop is Reference)
	assert_eq(10, prop.container.count(0.0))
	prop.write(12, 100.0)
	assert_eq(100.0, prop.read(-1))
	assert_eq(10, prop.container.size())
	assert_eq(12, prop.last_input_id)
	assert_eq(1, prop.container.count(100.0))
	prop.write(15, 200.0)
	assert_eq(100.0, prop.read(-2))
	assert_eq(200.0, prop.read(-1))
	assert_eq(15, prop.last_input_id)
	assert_eq(1, prop.container.count(200.0))
	assert_eq(3, prop.container.count(100.0))
	assert_eq(6, prop.container.count(0.0))
	assert_eq(200.0, prop.container[prop.last_index])
	assert_eq(200.0, prop.read(15))
	assert_eq(200.0, prop.read(16))
	assert_eq(0.0, prop.read(1))

func test_cb_contains():
	var prop = SyncPeer.CircularBuffer.new(10, 0.0)
	prop.write(12, 100.0)
	assert_false(prop.contains(13))
	assert_false(prop.contains(2))
	for i in range(3, 13):
		assert_true(prop.contains(i))
