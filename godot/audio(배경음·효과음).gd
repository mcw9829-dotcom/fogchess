extends Node
## Synthesized from sound.js by tools/build_audio.py; all original event schedules retained.
var enabled := true
var level := 1.0
var background: AudioStreamPlayer
var music_on := false
var gain := 0.0
var fade_constant := 2.5
var stop_after := 0.0
var played: Array[String] = []
const EVENTS = ["move","place","capture","fire","barrage","kill","victory","defeat","drawend","yourturn","scan"]

func cue(event: String) -> void:
	if not enabled or level<=0: return
	if event not in EVENTS: event = "move"
	played.append(event)
	if played.size()>32: played.pop_front()
	var player := AudioStreamPlayer.new()
	player.stream = load("res://sounds/%s.wav" % event)
	player.volume_db = linear_to_db(maxf(level,.00001))
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func set_level(value: float) -> void:
	level = clampf(value,0,1)
	fade_constant = .3

func music(on: bool) -> void:
	if on==music_on: return
	music_on = on
	fade_constant = 2.5 if on else .6
	stop_after = 0 if on else .9
	if not on: return
	if not is_instance_valid(background):
		background = AudioStreamPlayer.new()
		var stream: AudioStreamWAV = load("res://sounds/ambient.wav").duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
		background.stream = stream
		add_child(background)
	if not background.playing:
		gain = 0
		background.volume_db = -80
		background.play()

func _process(delta: float) -> void:
	if not is_instance_valid(background): return
	gain = lerpf(level if music_on else 0.0,gain,exp(-delta/fade_constant))
	background.volume_db = linear_to_db(maxf(gain,.00001))
	if stop_after>0:
		stop_after -= delta
		if stop_after<=0: background.stop()
