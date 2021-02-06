extends Node2D

const DEFAULT_SPEED = 100

var stopped = false

onready var _screen_size = get_viewport_rect().size

onready var synced = $synced
onready var aligned = $aligned
onready var area = $aligned/area

func _ready():
	synced.speed = DEFAULT_SPEED
	synced.direction = Vector2.LEFT

func _physics_process(delta):
	if not stopped:
		synced.speed += delta
		position += synced.speed * delta * synced.direction

	# !!! have to use some sort of separate coordinate storage when checking 
	# for interactions. Basically, we draw one set of things, but check 
	# for interactions another set of things.
	# OR at different time...
	var coord = area.global_position 

	# Check screen bounds to make ball bounce.
	if (coord.y < 0 and synced.direction.y < 0) or (coord.y > _screen_size.y and synced.direction.y > 0):
		synced.direction.y = -synced.direction.y

	# Check if scored
	if not SyncManager.is_client():
		if coord.x < 0:
			get_parent().update_score(false)
			_reset_ball(false)
		elif coord.x > _screen_size.x:
			get_parent().update_score(true)
			_reset_ball(true)

# called by paddle.gd when ball hits the paddle
func bounce(left):
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
