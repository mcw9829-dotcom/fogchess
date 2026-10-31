extends SceneTree
var app
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures += 1; push_error(label)
func settle() -> void:
	app._layout()
	await create_timer(.2).timeout
	app._layout()
	await create_timer(.2).timeout
func shot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func peer_message(peer: String, message: String) -> void:
	var response: Dictionary = await app.api.request("/chat",{"room":app.room,"token":peer,"text":message,"nonce":str(Time.get_ticks_usec())})
	check(response.get("ok",false),"opponent chat accepted by server")
	await app._poll()
	# Read acknowledgment happens after the text has completed layout.
	await create_timer(.2).timeout
func run() -> void:
	root.size = Vector2i(1440,1000)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer and child.name!="ChatReadVisibility": child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	await create_timer(.2).timeout
	for i in range(80):
		if not app.ui_motion.is_transition_busy(): break
		await create_timer(.05).timeout
	await app._select(Vector2i(7,5))
	app._message("")
	var chat = app.chat
	var peer: Dictionary = await app.api.request("/test-peer",{"room":app.room})
	await peer_message(peer.token,"안녕하세요! 좋은 대국 부탁드려요.")
	check(chat.unread==1 and chat.badge.visible and not chat.body.visible,"closed chat shows first unread badge")
	await app._poll()
	check(chat.unread==1,"poll does not double count")
	await create_timer(1.1).timeout
	await peer_message(peer.token,"채팅은 천천히 확인하셔도 됩니다.")
	check(chat.unread==2 and chat.badge_label.text=="2","second opponent message increments badge")
	var original_board: Vector2 = app.board.size
	for light in [false,true]:
		app.prefs.set_value("settings","light",light)
		app._apply_theme()
		app._render()
		for width in [1440,1120,390,320]:
			root.size = Vector2i(width,1000 if width==1440 else 760 if width==1120 else 844)
			app.page_scroll.scroll_vertical = 0
			await settle()
			check(app.game.get_global_rect().end.x<=width+1,"no horizontal overflow "+str([width,light]))
			check(chat.badge.get_global_rect().end.x<=chat.toggle.get_global_rect().end.x,"chat badge fits "+str([width,light]))
			check(chat.badge_label.text=="2","theme and resize retain unread "+str([width,light]))
			if width>760:
				check(app.match_ui.selection_position.size.x>=220,"selected action gets full card width "+str([width,light]))
			check(app.match_ui.self_rating.visible and "1458" in app.match_ui.self_rating.text,"separate player rating "+str([width,light]))
			check(app.self_line.text=="moon · 나" and app.match_ui.exposure_summary.visible,"identity and exposure are separate "+str([width,light]))
			check(app.match_ui.history_chips.filter(func(c): return c.visible).size()==3,"collapsed history shows three public moves "+str([width,light]))
			check(app.match_ui.history_chips[2].get_meta("notation").text=="Bf8","history uses actual saved notation "+str([width,light]))
			if width==1440: await shot("desktop-"+("light" if light else "dark"))
			if width==390:
				await shot("mobile-board-"+("light" if light else "dark"))
				app.page_scroll.ensure_control_visible(chat.toggle)
				await create_timer(.2).timeout
				app.page_scroll.scroll_vertical = int(app.page_scroll.get_v_scroll_bar().max_value)
				await create_timer(.3).timeout
				check(chat.toggle.get_global_rect().end.y<844,"mobile unread badge is reachable at page bottom")
				await shot("mobile-records-"+("light" if light else "dark"))
	root.size = Vector2i(1440,1000)
	app.page_scroll.scroll_vertical=0
	await settle()
	chat.toggle.pressed.emit()
	await settle()
	check(chat.body.visible and chat.unread==0 and not chat.badge.visible,"opening marks unread messages read")
	check(app.board.size.is_equal_approx(original_board),"opening chat keeps board size")
	await peer_message(peer.token,"메시지가 잘 보이나요?")
	check(chat.unread==0 and not chat.badge.visible,"open visible chat is already read")
	chat.entry.text = "작성 중인 메시지"
	chat.entry.caret_column = 3
	app._render()
	check(chat.entry.text=="작성 중인 메시지" and chat.entry.caret_column==3,"refresh preserves chat draft")
	await shot("chat-open-light")
	chat.toggle.pressed.emit()
	chat.entry.text="네, 잘 보여요."
	await chat.send()
	check(chat.unread==0,"own sent message never creates unread")
	check(chat.entry.text.is_empty(),"successful chat send clears draft")
	app.match_ui.history_toggle.pressed.emit()
	check(app.match_ui.history_chips.filter(func(c): return c.visible).size()==6,"expanded history shows available six moves")
	check(app.view.moveHistory.size()==6,"presentation leaves original history unchanged")
	await settle()
	await shot("history-expanded-light")
	var long_name: String = "긴플레이어이름테스트사용자"
	app.view.myName=long_name
	root.size=Vector2i(320,844)
	app._render()
	await settle()
	check(app.ui_shell.self_row.get_global_rect().end.x<=320,"long player name fits narrow mobile")
	var old_room: String = app.room
	app.room="different-test-room"
	chat.reset()
	check(chat.unread==0 and not chat.badge.visible and chat.entry.text.is_empty(),"room reset clears prior unread and draft")
	app.room=old_room
	print("READABILITY_CHECKS=",checks)
	print("FAILURES=",failures)
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
