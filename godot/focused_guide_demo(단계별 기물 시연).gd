extends "res://guide_demo(설명용 시연).gd"
## Reuses the original guide timeline; filters only which phase is replayed.
var all_frames: Array = []
var selected_stage := "move"
const STAGE_NAMES = {"move":"행마","attack":"공격","ability":"능력"}

func _ready() -> void:
	super._ready()
	# This larger scene is controlled by explicit tabs and playback buttons.
	for signal_name in ["mouse_entered","mouse_exited"]:
		for connection in get_signal_connection_list(signal_name):
			disconnect(signal_name,connection.callable)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	all_frames = frames.duplicate(true)
	set_stage(selected_stage,false)

func has_stage(stage: String) -> bool:
	var phase: String = STAGE_NAMES.get(stage,"")
	return all_frames.any(func(frame): return frame.get("phase","")==phase)

func set_stage(stage: String, autoplay: bool=true) -> bool:
	if not has_stage(stage): return false
	stop()
	selected_stage = stage
	var phase: String = STAGE_NAMES[stage]
	frames = all_frames.filter(func(frame): return frame.get("phase","")==phase).duplicate(true)
	index = 0
	elapsed = 0.0
	previous.clear()
	state.clear()
	fx.clear()
	apply_frame(0,true)
	if autoplay: start()
	return true

func restart() -> void:
	stop()
	start()
