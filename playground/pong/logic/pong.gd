extends Node2D

signal game_finished()

const SCORE_TO_WIN = 10

@onready var synced = $synced

@onready var score_left_node = $ScoreLeft
@onready var score_right_node = $ScoreRight
@onready var winner_left = $WinnerLeft
@onready var winner_right = $WinnerRight

func _ready():
	synced.score_left = 0
	synced.score_right = 0
	
	# We're in an authoritative multiplayer game now, yay!
	# Keep Server as the master of all nodes.
	# Instead, tell paddles to listen to input from proper source.
	if SyncManager.is_server():
		# For the server, give control of player2 to the other peer, player1 to self.
		$Player1/synced.belongs_to_peer_id = 0
		$Player2/synced.belongs_to_peer_id = get_tree().get_network_connected_peers()[0]
		print('SERVER: player2 belongs to another player %s' % get_tree().get_network_connected_peers()[0])
	elif SyncManager.is_client():
		# For the client, change control of player2 to self, leave player1 belonging to no one
		$Player2/synced.belongs_to_peer_id = 0
		print('CLIENT: player1 belongs to another player %s' % get_tree().get_network_connected_peers()[0])
	else:
		# Clicked "Play Scene" in Editor?..
		# Single player, no networkging enabled for some reason.
		# Let's control both players for the fun of it.
		$Player1/synced.belongs_to_peer_id = 0
		$Player2/synced.belongs_to_peer_id = 0
		print('OFFLINE: both players are controlled by local input')

func _process(_delta):
	score_left_node.set_text(str(synced.score_left))
	score_right_node.set_text(str(synced.score_right))

func update_score(add_to_left):
	if add_to_left:
		synced.score_left += 1
		score_left_node.set_text(str(synced.score_left))
	else:
		synced.score_right += 1
		score_right_node.set_text(str(synced.score_right))

	var game_ended = false
	if synced.score_left == SCORE_TO_WIN:
		winner_left.show()
		game_ended = true
	elif synced.score_right == SCORE_TO_WIN:
		winner_right.show()
		game_ended = true

	if game_ended:
		$ExitGame.show()
		$Ball.stop()

func _on_exit_game_pressed():
	emit_signal("game_finished")
