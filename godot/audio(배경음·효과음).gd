extends Node
## Original combat/UI cues and lobby-only music. Combat never starts a BGM.
var enabled := true
var level := 1.0
var played: Array[String] = []
const EVENTS = ["move","place","capture","fire","barrage","kill","victory","defeat","drawend","yourturn","scan","ui_click","ui_on","ui_off","ui_hover"]
var app
var background: AudioStreamPlayer
var music_gain := 0.0
var music_on := false
var last_ui_msec := -1000
var last_hover_msec := -1000
var last_pointer_msec := -1000

func _ready() -> void:
	app = get_parent()
	get_tree().node_added.connect(_on_node_added)
	for button in app.find_children("*","BaseButton",true,false): _bind_button(button)

func _on_node_added(node: Node) -> void:
	if node is BaseButton: _bind_button_ref.call_deferred(weakref(node))

func _bind_button_ref(reference: WeakRef) -> void:
	var button = reference.get_ref()
	if is_instance_valid(button) and not button.is_queued_for_deletion(): _bind_button(button)

func _bind_button(button: BaseButton) -> void:
	if not is_instance_valid(button) or not app.is_ancestor_of(button): return
	if button.has_meta("sound_connected"): return
	button.set_meta("sound_connected",true)
	button.set_meta("sound_bound_msec",Time.get_ticks_msec())
	button.pressed.connect(_on_button_pressed.bind(button))
	# Viewport enter signals can precede _input for the same mouse event.
	button.mouse_entered.connect(func(): button.set_meta("sound_hovered",true); _hover_button_ref.call_deferred(weakref(button)))
	button.mouse_exited.connect(func(): button.set_meta("sound_hovered",false))

func _hover_button_ref(reference: WeakRef) -> void:
	var button = reference.get_ref()
	if is_instance_valid(button) and not button.is_queued_for_deletion(): _on_button_hover(button)

func _input(event: InputEvent) -> void:
	# Ignore touch-emulated motion and stationary/layout-generated enter events.
	if event is InputEventMouseMotion and event.device!=-1 and event.relative.length_squared()>.01:
		last_pointer_msec = Time.get_ticks_msec()

func _on_button_hover(button: BaseButton) -> void:
	if not is_instance_valid(button): return
	if not enabled or level<=0 or button.disabled or not button.is_visible_in_tree(): return
	if not button.get_meta("sound_hovered",false): return
	if button.get_meta("silent_ui",false) or button.get_meta("silent_hover",false): return
	var now := Time.get_ticks_msec()
	if now-last_pointer_msec>80 or now-int(button.get_meta("sound_bound_msec",now))<180: return
	if now-last_hover_msec<140: return
	last_hover_msec = now
	cue("ui_hover")

func _on_button_pressed(button: BaseButton) -> void:
	if button.disabled or button.get_meta("silent_ui",false): return
	var event := "ui_on" if button.toggle_mode and button.button_pressed else ("ui_off" if button.toggle_mode else "ui_click")
	# Let the setting's callback update mute state before checking it.
	_play_ui.call_deferred(event)

func _play_ui(event: String) -> void:
	if not enabled or level<=0: return
	var now := Time.get_ticks_msec()
	if now-last_ui_msec<40: return
	last_ui_msec = now
	cue(event)

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
	for player in get_children():
		if player is AudioStreamPlayer and player!=background:
			player.volume_db = linear_to_db(maxf(level,.00001))

func _lobby_allowed() -> bool:
	return app.room.is_empty() and not app.replay.active and bool(app.prefs.get_value("settings","lobby_music",true)) and level>0

func _process(delta: float) -> void:
	music_on = _lobby_allowed()
	if music_on and not is_instance_valid(background):
		background = AudioStreamPlayer.new()
		background.name = "LobbyMusic"
		var stream: AudioStreamWAV = load("res://sounds/lobby.wav").duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(round(stream.get_length()*stream.mix_rate))
		background.stream = stream
		background.volume_db = -80
		add_child(background)
	if not is_instance_valid(background): return
	var target: float = level*.55 if music_on else 0.0
	music_gain = move_toward(music_gain,target,delta*(.55/1.2 if music_on else .55/.3))
	background.volume_db = linear_to_db(maxf(music_gain,.00001))
	if music_on and not background.playing: background.play()
	elif not music_on and music_gain<=.00001 and background.playing: background.stop()
