extends "res://addons/gut/test.gd"

var SyncProperty = null
var prop = null

func before_all():
	SyncProperty = load("res://sync/SyncProperty.gd")
	
func before_each():
	pass

func after_each():
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
	assert_eq(10, prop.container.size())
	assert_eq(12, prop.last_state_id)
	assert_eq(10, prop.container.count(100.0))
	prop.write(15, 200.0)
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
	assert_eq(SyncProperty.LINEAR_INTERPOLATION, prop.interpolation)
	assert_eq(SyncProperty.LINEAR_INTERPOLATION, prop.missing_state_interpolation)
	prop.resize(6)
	prop.write(11, 111.0)
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
	
	prop.write(19, 118.0)
	assert_eq(19, prop.last_state_id)
	assert_eq(118.0, prop.read(18.5)) # interpolation between equal values
	#gut.p('%s; last_state_id=%s, last_index=%s' % [prop.container, prop.last_state_id, prop.last_index])

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
	for i in range(12, 16):
		assert_eq(100.0+i, prop.container[prop._get_index(i)])
