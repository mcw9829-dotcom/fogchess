extends SceneTree
var app: Control
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures+=1; push_error(label)
func run() -> void:
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.prefs.set_value("settings","music",true) # Existing saved preference must not revive BGM.
	app._apply_theme()
	app._settings()
	check(app.find_children("Setting_music","",true,false).is_empty(),"retired BGM toggle is absent")
	check(app.find_children("Setting_sound","",true,false).size()==1,"effects toggle remains available")
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	for player in app.audio.get_children():
		if player is AudioStreamPlayer: player.stop(); player.queue_free()
	await process_frame
	await create_timer(.4).timeout
	check(not is_instance_valid(app.audio.background) or not app.audio.background.playing,"entering match has no music even with legacy music preference")
	var lengths = {"capture":.62,"fire":.98,"barrage":2.15,"kill":1.1,"victory":3.6,"defeat":3.4,"drawend":3.1}
	for event in app.audio.EVENTS:
		var sound = load("res://sounds/%s.wav" % event)
		check(sound is AudioStreamWAV and sound.get_length()>0,"audio resource imports: "+event)
		if event in lengths: check(abs(sound.get_length()-lengths[event])<.01,"new asset length: "+event)
	app.audio.played.clear()
	app.audio.enabled = true
	app.audio.set_level(.5)
	app._effect({"type":"capture","seq":10000,"cells":[[5,5]]})
	check(app.audio.played==["capture"],"capture confirmation routed once")
	app._effect({"type":"capture","seq":10000,"cells":[[5,5]]})
	check(app.audio.played.size()==1,"repeated server event cannot duplicate confirmation")
	app.board.piece_motion.clear()
	app.board.effects=true
	app.board.fx.reduced=false
	app._effect({"type":"barrage","seq":10001,"cells":[[5,6]],"from":[5,5],"confirmed_source":true})
	check(app.audio.played==["capture"],"cannon waits for ground-decal lead-in")
	await create_timer(.22).timeout
	check(app.audio.played==["capture","barrage"],"cannon fires once after lead-in")
	app.board.effects=false
	app._effect({"type":"barrage","seq":10002,"cells":[[5,6]],"from":[5,5],"confirmed_source":true})
	check(app.audio.played.size()==3,"effects-off mode still plays the cannon immediately")
	app.audio.enabled=false
	app.audio.cue("fire")
	check(app.audio.played.size()==3,"muted audio blocks redesigned cues")
	app.audio.enabled=true
	app.audio.set_level(0)
	app.audio.cue("victory")
	check(app.audio.played.size()==3,"zero volume blocks result cues")
	app._return_home()
	check(not app.audio.has_method("music"),"home and theme paths have no retired music playback")
	for player in app.audio.get_children():
		if player is AudioStreamPlayer: player.stop()
	app.queue_free()
	await process_frame
	print("AUDIO_CHECKS=%d" % checks)
	print("AUDIO_FAILURES=%d" % failures)
	quit(0 if failures==0 else 1)
