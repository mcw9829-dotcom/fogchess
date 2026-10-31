extends SceneTree
var app: Control
var checks := 0
var failures := 0
var pointer := Vector2.ZERO
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if ok: print("PASS: "+text)
	else: failures+=1;push_error(text)
func move_pointer(position: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=position
	event.global_position=position
	event.relative=position-pointer
	pointer=position
	root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1120,760)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.prefs.set_value("settings","lobby_music",false)
	var sound=app.audio
	var button:=Button.new()
	button.text="Hover target"
	button.position=Vector2(400,80)
	button.size=Vector2(120,50)
	button.z_index=100
	app.add_child(button)
	var other:=Button.new()
	other.position=Vector2(550,80)
	other.size=Vector2(120,50)
	other.z_index=100
	app.add_child(other)
	await create_timer(.25).timeout
	sound.played.clear()
	move_pointer(Vector2(390,60))
	move_pointer(Vector2(450,100))
	await process_frame
	check(sound.played==["ui_hover"],"real viewport mouse entry plays one hover cue")
	await create_timer(.18).timeout
	check(sound.played==["ui_hover"],"stationary pointer does not repeat hover")
	button.pressed.emit()
	await create_timer(.05).timeout
	check(sound.played==["ui_hover","ui_click"],"hover does not suppress the subsequent click")
	move_pointer(Vector2(600,100))
	await process_frame
	check(sound.played.back()=="ui_hover" and sound.played.size()==3,"moving to another enabled button plays hover")
	move_pointer(Vector2(450,100))
	await process_frame
	check(sound.played.size()==3,"fast sweep is rate-limited")
	await create_timer(.16).timeout
	move_pointer(Vector2(390,60))
	move_pointer(Vector2(450,100))
	await process_frame
	check(sound.played.size()==4,"re-entry after cooldown plays again")
	await create_timer(.16).timeout
	other.disabled=true
	move_pointer(Vector2(600,100))
	await process_frame
	check(sound.played.size()==4,"disabled buttons are silent")
	other.disabled=false
	sound.enabled=false
	move_pointer(Vector2(450,100))
	await process_frame
	check(sound.played.size()==4,"effects mute silences hover")
	sound.enabled=true
	sound.set_level(0)
	move_pointer(Vector2(600,100))
	await process_frame
	check(sound.played.size()==4,"zero volume silences hover")
	sound.set_level(.5)
	await create_timer(.1).timeout
	button.mouse_entered.emit()
	button.grab_focus()
	await process_frame
	check(sound.played.size()==4,"layout enter without pointer motion and keyboard focus are silent")
	await create_timer(.16).timeout
	var fresh:=Button.new()
	app.add_child(fresh)
	await process_frame
	move_pointer(Vector2(690,100))
	fresh.mouse_entered.emit()
	await process_frame
	check(sound.played.size()==4,"newly opened controls do not produce incidental hover sounds")
	var shot=load("res://sounds/fire.wav")
	var hover=load("res://sounds/ui_hover.wav")
	check(abs(shot.get_length()-.98)<.001,"precision shot resource is updated")
	check(abs(hover.get_length()-.085)<.001,"short hover resource is imported")
	sound.cue("fire")
	check(sound.played.back()=="fire","new shot remains on the existing fire event")
	app.board.fx.clear()
	for player in sound.get_children():
		if player is AudioStreamPlayer: player.stop()
	app.queue_free()
	await process_frame
	print("AUDIO_CHECKS=%d"%checks)
	print("AUDIO_FAILURES=%d"%failures)
	quit(0 if failures==0 else 1)
