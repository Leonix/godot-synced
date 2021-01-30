extends "res://addons/gut/test.gd"

var SyncProperty = null
var prop = null

func before_all():
	SyncProperty = load("res://sync/SyncProperty.gd")
	
func before_each():
	pass

func after_each():
	if prop:
		prop.free()
	prop = null

func after_all():
	SyncProperty = null

func test_no_interpolation():
	assert_null(prop)
	prop = SyncProperty.new({})
	assert_eq(SyncProperty.NO_INTERPOLATION, prop.interpolation)
	assert_eq(SyncProperty.NO_INTERPOLATION, prop.missing_state_interpolation)
	prop.resize(10)
	prop.write(12, 100.0)
	assert_eq(100.0, prop.last())
	assert_eq(10, prop.container.size())
	assert_eq(12, prop.last_state_id)
	assert_eq(12, prop.last_changed_state_id)
	assert_eq(10, prop.container.count(100.0))
	prop.write(15, 200.0)
	assert_eq(15, prop.last_changed_state_id)
	assert_eq(100.0, prop.last(1))
	assert_eq(200.0, prop.last(0))
	assert_eq(15, prop.last_state_id)
	assert_eq(1, prop.container.count(200.0))
	assert_eq(200.0, prop.container[prop.last_index])
	assert_eq(200.0, prop.read(15)) # int state id, no interpolation
	assert_eq(200.0, prop.read(16)) # (no)extrapolation
	assert_eq(100.0, prop.read(14.5)) # (no)interpolation between different values
	assert_eq(100.0, prop.read(13.5)) # (no)interpolation between equal values
	assert_eq(100.0, prop.read(1)) # value older than stored
	#gut.p('%s; last_state_id=%s, last_index=%s' % [prop.container, prop.last_state_id, prop.last_index])

func test_linear_interpolation():
	assert_null(prop)
	prop = SyncProperty.new({
		interpolation = SyncProperty.LINEAR_INTERPOLATION,
		missing_state_interpolation = SyncProperty.LINEAR_INTERPOLATION
	})
	assert_false(prop.ready_to_read())
	assert_false(prop.ready_to_write())
	assert_eq(SyncProperty.LINEAR_INTERPOLATION, prop.interpolation)
	assert_eq(SyncProperty.LINEAR_INTERPOLATION, prop.missing_state_interpolation)
	prop.resize(6)
	assert_false(prop.ready_to_read())
	assert_true(prop.ready_to_write())
	prop.write(11, 111.0)
	assert_true(prop.ready_to_read())
	assert_true(prop.ready_to_write())
	assert_eq(11, prop.last_state_id)
	prop.write(12, 112.0)
	assert_eq(12, prop.last_state_id)
	prop.write(14, 114.0)
	assert_eq(14, prop.last_state_id)
	prop.write(18, 118.0)
	assert_eq(18, prop.last_state_id)
	assert_eq(6, prop.container.size())
	
	assert_eq(118.0, prop.container[prop.last_index])
	assert_eq(114.0, prop.read(14)) # int state id, no interpolation
	assert_eq(120.0, prop.read(20)) # extrapolation into future int state
	assert_eq(120.3, prop.read(20.3)) # extrapolation into future float state
	assert_eq(115.0, prop.read(15)) # interpolation between different values, int
	assert_eq(113.5, prop.read(13.5)) # interpolation between different values, float
	assert_eq(113.0, prop.read(13)) # oldest value stored
	assert_eq(113.0, prop.read(12)) # value older than stored
	assert_eq(118.0, prop.last())
	assert_eq(117.0, prop.last(1))
	assert_eq(18, prop.last_changed_state_id)
	
	prop.write(19, 118.0)
	assert_eq(18, prop.last_changed_state_id)
	assert_eq(118.0, prop.last())
	assert_eq(118.0, prop.last(1))
	assert_eq(117.0, prop.last(2))
	assert_eq(19, prop.last_state_id)
	assert_eq(118.0, prop.read(18.5)) # interpolation between equal values
	#gut.p('%s; last_state_id=%s, last_index=%s' % [prop.container, prop.last_state_id, prop.last_index])

func test_changed():
	assert_null(prop)
	prop = SyncProperty.new({})
	prop.resize(10)
	prop.write(11, 111.0)
	assert_eq(11, prop.last_changed_state_id)
	assert_true(prop.changed(10))
	assert_false(prop.changed(11))
	prop.write(12, 112.0)
	assert_true(prop.changed(11))
	assert_false(prop.changed(12))
	assert_true(prop.changed(11, 12))
	prop.write(13, 113.0)
	assert_eq(13, prop.last_changed_state_id)
	prop.write(14, 114.0)
	prop.write(15, 115.0)
	prop.write(16, 116.0)
	assert_eq(16, prop.last_changed_state_id)
	prop.write(17, 116.0)
	assert_eq(16, prop.last_changed_state_id)
	prop.write(20, 116.0)
	assert_eq(16, prop.last_changed_state_id)	
	assert_true(prop.changed(11))
	assert_true(prop.changed(15))
	assert_true(prop.changed(15, 16))
	assert_true(prop.changed(15, 20))
	assert_false(prop.changed(16))
	assert_false(prop.changed(16, 17))
	assert_false(prop.changed(16, 20))
	prop.write(24, 124.0)
	assert_eq(24, prop.last_changed_state_id)	
	assert_true(prop.changed(15))
	assert_true(prop.changed(16))
	assert_true(prop.changed(20))

func test_get_negative():
	assert_null(prop)
	prop = SyncProperty.new({})
	prop.resize(4)
	prop.write(11, 111.0)
	prop.write(12, 112.0)
	prop.write(13, 113.0)
	prop.write(14, 114.0)
	assert_eq(114.0, prop._get(-1))

func test_get_index():
	assert_null(prop)
	prop = SyncProperty.new({})
	prop.resize(4)
	prop.write(11, 111.0)
	prop.write(12, 112.0)
	prop.write(13, 113.0)
	prop.write(14, 114.0)
	prop.write(15, 115.0)
	assert_eq(15, prop.last_state_id)
	assert_eq(112.0, prop.container[prop._get_index(11)])
	assert_eq(115.0, prop.container[prop._get_index(16)])
	for i in range(12, 16):
		assert_eq(100.0+i, prop.container[prop._get_index(i)])

func test_shouldsend_reliable_unreliable(strat=use_parameters([SyncProperty.RELIABLE_SYNC, SyncProperty.UNRELIABLE_SYNC])):
	prop = SyncProperty.new({
		sync_strategy = strat,
		strat_stale_delay = 2
	})
	assert_eq(strat, prop.sync_strategy)
	prop.resize(10)
	prop.write(11, 111.0)
	prop.write(15, 115.0)
	assert_eq([strat, 115.0], prop.shouldsend(14))
	assert_null(prop.shouldsend(15))
	prop.write(17, 115.0)
	assert_eq(15, prop.last_changed_state_id)
	assert_false(prop.changed(15))
	assert_eq([strat, 115.0], prop.shouldsend(14))
	assert_eq([strat, 115.0], prop.shouldsend(12))
	assert_null(prop.shouldsend(15))
	assert_null(prop.shouldsend(17))
	assert_null(prop.shouldsend(18))
	prop.write(19, 115.0)
	assert_eq([strat, 115.0], prop.shouldsend(12))
	assert_null(prop.shouldsend(17))

func test_shouldsend_auto():
	var strat = SyncProperty.AUTO_SYNC
	prop = SyncProperty.new({
		sync_strategy = strat,
		strat_stale_delay = 2
	})
	assert_eq(strat, prop.sync_strategy)
	prop.resize(10)
	prop.write(11, 111.0)
	prop.write(15, 115.0)
	assert_eq([strat, 115.0], prop.shouldsend(14))
	assert_null(prop.shouldsend(15))
	prop.write(17, 115.0)
	assert_eq(15, prop.last_changed_state_id)
	assert_false(prop.changed(15))
	assert_eq([strat, 115.0], prop.shouldsend(14))
	assert_eq([strat, 115.0], prop.shouldsend(12))
	assert_null(prop.shouldsend(15))
	assert_null(prop.shouldsend(17))
	assert_null(prop.shouldsend(18))
	prop.write(18, 115.0)
	assert_eq([SyncProperty.RELIABLE_SYNC, 115.0], prop.shouldsend(13))
	assert_null(prop.shouldsend(17))
	prop.write(21, 116.0)
	assert_eq([strat, 116.0], prop.shouldsend(20))

func test_shouldsend_do_not_sync():
	var strat = SyncProperty.DO_NOT_SYNC
	prop = SyncProperty.new({
		sync_strategy = strat,
		strat_stale_delay = 2
	})
	assert_eq(strat, prop.sync_strategy)
	prop.resize(10)
	prop.write(11, 111.0)
	prop.write(15, 115.0)
	assert_null(prop.shouldsend(14))
	assert_null(prop.shouldsend(15))
	prop.write(17, 115.0)
	assert_eq(15, prop.last_changed_state_id)
	assert_false(prop.changed(15))
	assert_null(prop.shouldsend(14))
	assert_null(prop.shouldsend(12))
	assert_null(prop.shouldsend(15))
	assert_null(prop.shouldsend(17))
	assert_null(prop.shouldsend(18))
	prop.write(18, 115.0)
	assert_null(prop.shouldsend(13))
	assert_null(prop.shouldsend(17))
	prop.write(21, 116.0)
	assert_null(prop.shouldsend(20))
