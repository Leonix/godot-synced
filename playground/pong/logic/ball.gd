extends Node2D

const DEFAULT_SPEED = 100

var stopped = false

onready var _screen_size = get_viewport_rect().size

onready var synced = $synced
onready var area = $Aligned/area

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
	if SyncManager.is_server():
		if coord.x < 0:
			get_parent().update_score(false)
			_reset_ball(false)
		elif coord.x > _screen_size.x:
			get_parent().update_score(true)
			_reset_ball(true)

# called by paddle.gd when ball hits the paddle
func bounce(left, random):
	reset_history()
	if left:
		synced.direction.x = abs(synced.direction.x)
	else:
		synced.direction.x = -abs(synced.direction.x)
	synced.speed *= 1.1
	if SyncManager.is_client():
		# On client, we can't (or rather don't bother to) predict server-side random.
		# If we do random here on Client, ball occasionally has to do weird things.
		# We juse set this to zero, it always looks reasonably well.
		synced.direction.y = 0
	else:
		synced.direction.y = random * 2.0 - 1
	synced.direction = synced.direction.normalized()

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

# !!! TODO use Aligned when implemented
func reset_history():
	synced.rollback('position')
	synced.rollback('direction')
