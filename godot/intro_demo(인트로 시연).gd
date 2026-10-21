extends "res://original_demo(원본 시연 재현).gd"
var lesson := 0

func _ready() -> void:
	intro = true
	cols = 8
	running = true
	spec = scenes().intro[lesson]
	frames = spec.frames
	custom_minimum_size = Vector2(212,212)
	super._ready()
