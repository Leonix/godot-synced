#
# 
#

extends Node
class_name SyncBase

var _spawner: SyncBase = null

func _init(spawner:SyncBase = null):
	_spawner = spawner

func _ready():
	SyncManager.SyncBase_created(self, _spawner)
