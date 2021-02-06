extends Node2D

const DEFAULT_SPEED = 100

var stopped = false

onready var _screen_size = get_viewport_rect().size

onready var synced = $synced
onready var aligned = $aligned
onready var area = $aligned/area

func _ready():
	synced.speed = DEFAULT_SPEED
	synced.direction = Vector2.RIGHT

func _physics_process(delta):
	if not stopped:
		synced.speed += delta
		position += synced.speed * delta * synced.direction

	# Check screen bounds to make ball bounce.
	if (position.y < 0 and synced.direction.y < 0) or (position.y > _screen_size.y and synced.direction.y > 0):
		synced.direction.y = -synced.direction.y

	# Check if scored
	if not SyncManager.is_client():
		if aligned.position.x < 0:
			get_parent().update_score(false)
			_reset_ball(false)
		elif aligned.position.x > _screen_size.x:
			get_parent().update_score(true)
			_reset_ball(true)

# called by paddle.gd when ball hits the paddle
func bounce(left):
	aligned.touch('position')
	aligned.direction = Vector2(
		abs(aligned.direction.x)*(1 if left else -1),
		fmod(aligned.direction.y * 140.314 + 0.47, 1.0) - 0.5
	).normalized()
	synced.speed *= 1.1

# called by pong.gd when the game ends
func stop():
	stopped = true

func _reset_ball(for_left):
	position = _screen_size / 2
	if for_left:
		synced.direction = Vector2.LEFT
	else:
		synced.direction = Vector2.RIGHT
	synced.speed = DEFAULT_SPEED
