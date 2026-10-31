extends SceneTree
var app: Control
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if ok: print("PASS: "+text)
	else: failures+=1; push_error(text)
func run() -> void:
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.4).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	var sound=app.audio
	check(sound.music_on and is_instance_valid(sound.background) and sound.background.playing,"lobby music starts on home")
	check(sound.background.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and sound.background.stream.loop_end==1411200,"32-second loop uses exact sample boundary")
	var bg=sound.background
	app._settings()
	await create_timer(.1).timeout
	check(sound.background==bg and sound.background.playing,"opening settings keeps music without restarting player")
	check(app.find_children("Setting_lobby_music","",true,false).size()==1,"lobby-specific music switch exists")
	check(app.find_children("Setting_music","",true,false).is_empty(),"combat music switch stays absent")
	var music_switch=app.find_children("Setting_lobby_music","",true,false)[0]
	music_switch.button_pressed=false
	await create_timer(.4).timeout
	check(not sound.background.playing,"lobby switch fades out and stops music")
	music_switch.button_pressed=true
	await create_timer(.15).timeout
	check(sound.background.playing,"lobby switch resumes music")
	var button=Button.new()
	app.add_child(button)
	await process_frame
	await process_frame
	sound.played.clear()
	button.mouse_entered.emit()
	button.focus_entered.emit()
	await process_frame
	check(sound.played.is_empty(),"layout hover without pointer motion and focus remain silent")
	button.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played==["ui_click"],"button activation plays one click")
	sound._bind_button(button)
	button.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played==["ui_click","ui_click"],"rebinding cannot duplicate click sound")
	button.disabled=true
	button.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played.size()==2,"disabled buttons are silent")
	button.disabled=false
	button.toggle_mode=true
	button.button_pressed=true
	await create_timer(.06).timeout
	check(sound.played.size()==2,"programmatic toggle changes remain silent")
	button.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played.back()=="ui_on","activated ON toggle plays ascending cue")
	button.button_pressed=false
	button.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played.back()=="ui_off","activated OFF toggle plays descending cue")
	var mute=app.find_children("Setting_sound","",true,false)[0]
	sound.played.clear()
	mute.button_pressed=false
	mute.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played.is_empty() and sound.background.playing,"effects mute silences UI but keeps independent lobby music")
	mute.button_pressed=true
	mute.pressed.emit()
	await create_timer(.06).timeout
	check(sound.played==["ui_on"],"enabling sound gives one toggle cue and no old place cue")
	for event in ["fire","ui_click","ui_on","ui_off"]:
		var stream=load("res://sounds/%s.wav" % event)
		check(stream is AudioStreamWAV and stream.get_length()>0,"new cue loads: "+event)
	check(abs(load("res://sounds/fire.wav").get_length()-.98)<.01,"precision shot replaces the old suppressed asset")
	var fixture: Dictionary=await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	await create_timer(.4).timeout
	check(not sound.music_on and not sound.background.playing,"entering match stops lobby music")
	app._settings()
	await create_timer(.1).timeout
	check(not sound.background.playing,"opening settings during match cannot restart lobby music")
	app._return_home()
	await create_timer(.2).timeout
	check(sound.music_on and sound.background.playing,"returning home resumes lobby music")
	app.replay.active=true
	await create_timer(.4).timeout
	check(not sound.background.playing,"replay suppresses lobby music even without room")
	app.replay.active=false
	await create_timer(.2).timeout
	sound.set_level(0)
	await create_timer(.4).timeout
	var before=sound.played.size()
	sound.cue("ui_click")
	check(not sound.background.playing and sound.played.size()==before,"zero master volume silences music and cues")
	app.board.fx.clear()
	for player in sound.get_children():
		if player is AudioStreamPlayer: player.stop()
	app.queue_free()
	await process_frame
	print("AUDIO_CHECKS=%d" % checks)
	print("AUDIO_FAILURES=%d" % failures)
	quit(0 if failures==0 else 1)
