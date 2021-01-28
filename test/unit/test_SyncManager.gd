extends "res://addons/gut/test.gd"

var SyncManagerResource = null
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
	SyncManagerResource = load("res://sync/SyncManager.gd")
	__input_frames_min_batch = SyncManager.input_frames_min_batch
	
func before_each():
	obj = SyncManagerResource.new()

func after_each():
	if obj:
		obj.free()
	obj = null
	SyncManager.input_frames_min_batch = __input_frames_min_batch

func after_all():
	SyncManagerResource = null

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
