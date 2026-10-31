extends SceneTree
var app
var checks := 0
var failures := 0
var peer := ""
var message_id := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures += 1; push_error(label)
func settle() -> void:
	app._layout()
	await create_timer(.25).timeout
	app._layout()
	await create_timer(.25).timeout
func shot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func message(text: String) -> void:
	await create_timer(1.05).timeout
	message_id += 1
	var reply: Dictionary = await app.api.request("/chat",{"room":app.room,"token":peer,"text":text,"nonce":"qa-"+str(message_id)})
	check(reply.get("ok",false),"opponent message accepted "+str(message_id))
	await app._poll()
	await create_timer(.3).timeout
func run() -> void:
	root.size = Vector2i(390,844)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.4).timeout
	for child in app.get_children():
		if child is Timer and child.name!="ChatReadVisibility": child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	check(fixture.has("room"),"isolated room exists")
	if not fixture.has("room"): quit(2); return
	app._enter(fixture)
	await app._poll()
	await create_timer(1.8).timeout
	var peer_reply: Dictionary = await app.api.request("/test-peer",{"room":app.room})
	peer = peer_reply.token
	var chat = app.chat
	var nav = app.ui_shell.mobile_navigation
	chat.toggle.pressed.emit()
	await settle()
	app.page_scroll.scroll_vertical = 0
	await message("화면 아래에서 기다리는 메시지입니다.")
	check(chat.body.visible and chat.transcript.global_position.y>844,"expanded transcript is below the phone viewport")
	check(chat.unread==1 and chat.badge.visible,"offscreen expanded message stays unread")
	check(nav.chat_badge.is_visible_in_tree() and nav.chat_count.text=="1" and not chat.notice.visible,"fixed mobile footer exposes unread without duplicate header notice")
	await app._poll()
	await create_timer(.2).timeout
	check(chat.unread==1,"repeated poll does not count a message twice")
	chat.entry.text = "아직 보내지 않은 초안"
	chat.entry.caret_column = 4
	for light in [false,true]:
		app.prefs.set_value("settings","light",light)
		app._apply_theme()
		for dims in [Vector2i(320,740),Vector2i(390,844),Vector2i(844,390)]:
			root.size = dims
			app.page_scroll.scroll_vertical = 0
			await settle()
			check(chat.unread==1,"resize and theme retain unread "+str([dims,light]))
			check(nav.chat_badge.is_visible_in_tree(),"footer unread visible "+str([dims,light]))
			check(app.match_ui.chrome.get_global_rect().end.x<=dims.x+1,"header remains inside viewport "+str([dims,light]))
			check(nav.chat_button.size.x>=44 and nav.chat_button.size.y>=44,"footer keeps 44px touch target "+str([dims,light]))
			if dims.x==390: shot("chat-mobile-notice-"+("light" if light else "dark"))
			if dims.x==320: shot("chat-narrow-notice-"+("light" if light else "dark"))
	root.size = Vector2i(390,844)
	await settle()
	nav.chat_button.pressed.emit()
	await settle()
	await create_timer(.2).timeout
	check(chat._can_read_latest(),"notice scrolls actual messages into view")
	check(chat.unread==0 and not nav.chat_badge.visible and not chat.badge.visible,"read clears footer and card badges")
	check(chat.entry.text=="아직 보내지 않은 초안" and chat.entry.caret_column==4,"notice navigation preserves draft")
	check(not chat.entry.has_focus(),"notice does not open a phone keyboard")
	shot("chat-open-mobile")
	# Folded chat must remain unread; a collapsed card near the viewport is insufficient.
	chat.toggle.pressed.emit()
	await message("접어 둔 채팅은 읽지 않은 상태입니다.")
	check(chat.unread==1,"collapsed message remains unread")
	nav.chat_button.pressed.emit()
	await settle()
	check(chat.unread==0,"second navigation reads latest message")
	root.size = Vector2i(1440,1000)
	app.page_scroll.scroll_vertical = 0
	await settle()
	if app.controls_scroll.is_ancestor_of(chat.body): app.controls_scroll.ensure_control_visible(chat.body)
	await settle()
	app._help()
	await create_timer(.3).timeout
	await message("기물 설명창 뒤에 도착한 메시지입니다.")
	check(chat.unread==1 and not chat._can_read_latest(),"exclusive dialog blocks read acknowledgment")
	shot("chat-covered-by-help")
	for child in app.get_children():
		if child is Window: child.hide(); child.queue_free()
	await settle()
	check(chat.unread==0,"closing dialog reads visible transcript without another poll")
	# Scroll older chat: arrival cannot acknowledge an unseen last line.
	var messages: Array = app.view.get("chat",[]).duplicate(true)
	var next_id: int = chat.last_id
	for i in range(24):
		next_id += 1
		messages.append({"id":next_id,"side":"B","name":"QA 상대","text":"이전 대화 %d · 읽음 위치 검증" % i})
	app.view.chat = messages
	chat.render()
	await settle()
	check(chat.unread==0,"visible newest batch becomes read")
	chat.transcript.get_v_scroll_bar().value = 0
	await create_timer(.2).timeout
	next_id += 1
	app.view.chat.append({"id":next_id,"side":"B","name":"QA 상대","text":"맨 아래에 도착한 새 메시지"})
	chat.render()
	await settle()
	check(chat.unread==1,"reading old lines does not acknowledge latest message")
	chat._scroll_to_bottom()
	await settle()
	check(chat.unread==0,"scrolling to latest clears unread")
	chat.body.hide()
	next_id += 1
	app.view.chat.append({"id":next_id,"side":app.view.yourColor,"name":"나","text":"내 메시지"})
	chat.render()
	await settle()
	check(chat.unread==0,"own message creates no unread badge")
	chat.unread = 103
	chat._title()
	check(chat.badge_label.text=="99+" and chat.notice_count.text=="99+","large badge uses 99+")
	app.replay.active = true
	chat.render()
	check(not chat.notice.visible and not chat.card.visible,"replay hides participant chat and notice")
	app.replay.active = false
	chat.reset()
	check(chat.unread==0 and chat.entry.text.is_empty() and not chat.notice.visible,"room reset clears state")
	# End-state display uses server reason; legacy games retain their fallback.
	await app._act({"type":"resign"})
	for item in [["disconnect","접속 끊김"],["timeout","미행동 3회"],["resign","기권"],["king","내 왕이 당했다"]]:
		app.view.endReason = item[0]
		app.view.log = ["상대가 기권했습니다."]
		await app.game_display._render_result()
		check(item[1] in app.result_sub.text,"authoritative result reason "+item[0])
	app.view.erase("endReason")
	app.view.log = ["접속 끊김으로 종료", "상대가 기권했습니다."]
	await app.game_display._render_result()
	check("접속 끊김" in app.result_sub.text,"legacy replay reason fallback remains")
	print("CHAT_QA_CHECKS=",checks)
	print("FAILURES=",failures)
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)
