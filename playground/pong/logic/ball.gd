extends Area2D

const DEFAULT_SPEED = 100

var direction = Vector2.LEFT
var stopped = false
var _speed = DEFAULT_SPEED

onready var _screen_size = get_viewport_rect().size

onready var synced = $synced

func _physics_process(delta):
	# Don't have to do anything here unless we're the server.
	# (We may still run the code, but it won't do anything since 
	# all synced properties are write-protected on Client)
	if SyncManager.is_client():
		return

	if not stopped:
		_speed += delta
		position += _speed * delta * direction

	# Check screen bounds to make ball bounce.
	if (position.y < 0 and direction.y < 0) or (position.y > _screen_size.y and direction.y > 0):
		direction.y = -direction.y

	# Check if scored
	if position.x < 0:
		get_parent().update_score(false)
		_reset_ball(false)
	elif position.x > _screen_size.x:
		get_parent().update_score(true)
		_reset_ball(true)

# called by paddle.gd when ball hits the paddle
func bounce(left, random):
	if left:
		direction.x = abs(direction.x)
	else:
		direction.x = -abs(direction.x)
	_speed *= 1.1
	direction.y = random * 2.0 - 1
	direction = direction.normalized()

# called by pong.gd when the game ends
func stop():
	stopped = true

func _reset_ball(for_left):
	position = _screen_size / 2
	if for_left:
		direction = Vector2.LEFT
	else:
		direction = Vector2.RIGHT
	_speed = DEFAULT_SPEED
