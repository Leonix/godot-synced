extends Node

class_name SyncInput

func _ready():
	pass

class SyncInputFacade:
	func _init():
		pass

	signal _input

	func is_action_pressed(action: String)->bool:
		return false

	func is_action_just_pressed(action: String)->bool:
		return false

	func is_action_just_released(action: String)->bool:
		return false

	func get_action_strength()->float:
		return 0.0

	func action_press(action: String)->void:
		assert(false, 'SyncInput->action_press() is not implemented')
		
	func action_release(action: String)->void:
		assert(false, 'SyncInput->action_release() is not implemented')
