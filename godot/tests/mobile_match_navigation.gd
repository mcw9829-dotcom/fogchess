extends SceneTree
var app
var checks:=0
var failures:Array[String]=[]
var tapped_count:=0
var dragged_count:=0
var history_pressed:=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1;print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)
func wait_layout():
	app._layout();await create_timer(.25).timeout;app._layout();await create_timer(.25).timeout
func shot(name:String):
	await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func touch(point:Vector2,down:bool):
	var event:=InputEventScreenTouch.new();event.position=point;event.index=0;event.pressed=down
	Input.parse_input_event(event);await process_frame
func tap(control:Control):
	var point:Vector2=control.get_global_rect().get_center()
	await touch(point,true);await touch(point,false);await create_timer(.35).timeout
func swipe(start:Vector2,finish:Vector2):
	await touch(start,true)
	var previous:=start
	for i in range(1,9):
		var point:=start.lerp(finish,i/8.0)
		var event:=InputEventScreenDrag.new();event.index=0;event.position=point;event.relative=point-previous;event.screen_relative=event.relative
		Input.parse_input_event(event);previous=point;await process_frame
	await touch(finish,false);await create_timer(.25).timeout
func run():
	Input.emulate_mouse_from_touch=true
	root.size=Vector2i(390,844);app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app);await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer and child.name!="ChatReadVisibility":child.stop()
	app.audio.enabled=false
	var fixture:Dictionary=await app.api.request("/test-focus",{})
	app._enter(fixture);await app._poll();await create_timer(2).timeout;await wait_layout()
	var nav=app.ui_shell.mobile_navigation
	app.chat.native_button.hide() # Browser/mobile has no Windows IME fallback button.
	check(nav.bar.visible,"mobile navigation visible in match")
	check(not nav.bar.get_global_rect().intersects(app.page_scroll.get_global_rect()),"navigation reserves space outside board page")
	await shot("mobile-board-390-dark")
	await tap(nav.history_button)
	check(app.match_ui.history_expanded,"touch shortcut expands move history")
	check(nav._history_target().get_global_rect().intersects(app.page_scroll.get_global_rect()),"touch shortcut reaches combat record")
	await shot("mobile-record-390-dark")
	var before:int=app.page_scroll.scroll_vertical
	var page:Rect2=app.page_scroll.get_global_rect()
	await swipe(Vector2(page.position.x+7,page.position.y+page.size.y*.35),Vector2(page.position.x+7,page.position.y+page.size.y*.65))
	print("SWIPE_RECORD_SCROLL ",before," -> ",app.page_scroll.scroll_vertical)
	check(app.page_scroll.scroll_vertical<before,"finger swipe outside board scrolls record page")
	await tap(nav.chat_button)
	check(app.chat.body.visible and app.chat.transcript.get_global_rect().intersects(app.page_scroll.get_global_rect()),"touch shortcut opens and reaches chat")
	check(not app.chat.entry.has_focus(),"chat reading does not open input keyboard")
	await shot("mobile-chat-390-dark")
	await tap(nav.board_button)
	check(app.page_scroll.scroll_vertical==0,"touch shortcut returns to board")
	app.board.tapped.connect(func(_cell):tapped_count+=1)
	app.board.dragged.connect(func(_from,_to):dragged_count+=1)
	var pawn:Vector2=app.board.global_position+app.board.center(Vector2i(5,8))
	await touch(pawn,true);await touch(pawn,false);await create_timer(.3).timeout
	check(tapped_count==1,"normal touch still reaches board tap")
	check(not app.selection.is_empty(),"normal touch still selects own piece")
	app._clear_selection()
	before=app.page_scroll.scroll_vertical
	var origin:Vector2=app.board.global_position+app.board.center(Vector2i(6,3))
	await swipe(origin,origin-Vector2(0,90))
	check(app.page_scroll.scroll_vertical==before,"board swipe does not scroll page")
	check(dragged_count==1,"board drag still follows piece input path")
	# Starting a swipe on an ordinary button must scroll without clicking it.
	await tap(nav.history_button)
	app.match_ui.history_toggle.pressed.connect(func():history_pressed+=1)
	app.page_scroll.ensure_control_visible(app.match_ui.history_toggle);await create_timer(.2).timeout
	var history_start:Vector2=app.match_ui.history_toggle.get_global_rect().get_center()
	before=app.page_scroll.scroll_vertical
	await swipe(history_start,history_start+Vector2(0,100))
	check(app.page_scroll.scroll_vertical<before,"swipe can begin on a record disclosure")
	check(history_pressed==0 and app.match_ui.history_expanded,"record swipe never clicks the disclosure")
	# Mobile navigation stays usable in both themes and landscape, with no overlap.
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		for dims in [Vector2i(320,740),Vector2i(390,844),Vector2i(844,390)]:
			root.size=dims;await wait_layout();await tap(nav.board_button)
			check(nav.bar.visible and app.get_viewport_rect().encloses(nav.bar.get_global_rect()),"footer fits "+str([dims,light]))
			check(not nav.bar.get_global_rect().intersects(app.page_scroll.get_global_rect()),"footer avoids page "+str([dims,light]))
			for button in nav.buttons.values():check(button.size.x>=44 and button.size.y>=44,"44px touch target "+str([dims,light,button.text]))
			await shot("board-%d-%s" % [dims.x,"light" if light else "dark"])
			await tap(nav.history_button)
			check(nav._history_target().get_global_rect().intersects(app.page_scroll.get_global_rect()),"record reachable "+str([dims,light]))
			await shot("record-%d-%s" % [dims.x,"light" if light else "dark"])
			await tap(nav.chat_button)
			check(app.chat.transcript.get_global_rect().intersects(app.page_scroll.get_global_rect()),"chat reachable "+str([dims,light]))
			check(not app.chat.entry.has_focus(),"chat navigation does not focus keyboard "+str([dims,light]))
			check(nav.selected=="chat" and nav.chat_button.button_pressed,"chat shortcut remains selected "+str([dims,light]))
			await shot("chat-%d-%s" % [dims.x,"light" if light else "dark"])
			await tap(nav.board_button)
			check(app.page_scroll.scroll_vertical==0,"board return "+str([dims,light]))
	# A real peer message appears once in the fixed footer and is read on arrival.
	root.size=Vector2i(390,844);await wait_layout();await tap(nav.board_button)
	var peer:Dictionary=await app.api.request("/test-peer",{"room":app.room})
	var sent:Dictionary=await app.api.request("/chat",{"room":app.room,"token":peer.token,"text":"모바일 알림 확인","nonce":"mobile-nav-1"})
	check(sent.get("ok",false),"isolated peer chat sends")
	await app._poll();await create_timer(.3).timeout
	check(app.chat.unread==1 and nav.chat_badge.visible and nav.chat_count.text=="1","footer shows unread message")
	check(not app.chat.notice.visible,"header does not duplicate footer notification")
	await shot("unread-390-light")
	await tap(nav.chat_button);await create_timer(.3).timeout
	check(app.chat.unread==0 and not nav.chat_badge.visible,"chat arrival clears visible latest unread")
	# Long message history consumes the same gesture inside its own viewport.
	app.chat.transcript.text="\n".join(PackedStringArray(range(35).map(func(i):return "이전 채팅 %d" % i)))
	await create_timer(.2).timeout
	app.chat.transcript.get_v_scroll_bar().value=0
	var text_page:Rect2=app.chat.transcript.get_global_rect();before=app.page_scroll.scroll_vertical
	print("CHAT_SCROLL_GEOMETRY ",text_page," page ",app.page_scroll.get_global_rect()," range ",app.chat.transcript.get_v_scroll_bar().value," ",app.chat.transcript.get_v_scroll_bar().max_value," ",app.chat.transcript.get_v_scroll_bar().page)
	await swipe(text_page.get_center()+Vector2(0,24),text_page.get_center()-Vector2(0,24))
	print("CHAT_SCROLL_AFTER ",app.chat.transcript.get_v_scroll_bar().value)
	check(app.chat.transcript.get_v_scroll_bar().value>0,"chat history finger swipe scrolls messages")
	check(absf(app.chat.transcript.get_v_scroll_bar().value-48)<=1,"chat swipe distance is not multiplied by mouse emulation")
	check(app.page_scroll.scroll_vertical==before,"chat history swipe does not double-scroll page")
	# Rapid shortcuts cannot let an old awaited chat jump override the new board destination.
	nav.jump_to("chat");nav.jump_to("board");await create_timer(.4).timeout
	check(app.page_scroll.scroll_vertical==0,"rapid chat to board keeps latest destination")
	await tap(nav.history_button)
	page=app.page_scroll.get_global_rect();var modal_start:=Vector2(page.position.x+7,page.position.y+150)
	await touch(modal_start,true)
	var pan:=InputEventScreenDrag.new();pan.index=0;pan.position=modal_start+Vector2(0,30);pan.relative=Vector2(0,30);Input.parse_input_event(pan);await process_frame
	var modal:Array=app._small_window("QA 확인",280,280);await create_timer(.1).timeout
	before=app.page_scroll.scroll_vertical
	pan=InputEventScreenDrag.new();pan.index=0;pan.position=modal_start+Vector2(0,90);pan.relative=Vector2(0,60);Input.parse_input_event(pan);await process_frame
	check(not nav.swiping and app.page_scroll.scroll_vertical==before,"opening a modal cancels an active page swipe")
	await touch(modal_start+Vector2(0,90),false);modal[0].queue_free();await process_frame
	# Ability preview is never converted into page scroll or a duplicate command.
	fixture=await app.api.request("/test-fixture",{"scenario":"piece_Q"})
	app._enter(fixture);await app._poll();await create_timer(1.8).timeout
	root.size=Vector2i(390,844);await wait_layout();await app._select(Vector2i(6,6));app._choose_action("scan");await create_timer(.2).timeout
	var assist=app.ui_shell.aim_assist
	var turn:int=app.view.turnCount
	var target:=Vector2i(5,7)
	var aim_point:Vector2=app.board.global_position+app.board.center(target)
	before=app.page_scroll.scroll_vertical
	await swipe(aim_point,aim_point+Vector2(10,20))
	check(assist.pending.x>=0 and app.view.turnCount==turn,"ability swipe only previews one target")
	check(app.page_scroll.scroll_vertical==before,"ability swipe never scrolls board page")
	check(assist.footer.visible and not assist.footer.get_global_rect().intersects(nav.bar.get_global_rect()),"aim confirmation and footer have separate slots")
	await shot("aim-and-navigation-390")
	await tap(nav.history_button)
	check(assist.pending.x<0 and app.view.turnCount==turn,"record navigation cancels stale aim without firing")
	await tap(nav.board_button)
	check(nav.chat_button.disabled,"solo practice disables unavailable chat")
	# Setup primary action and queue banner coexist with the same navigation.
	await app._join({"vs_bot":true,"level":"easy"});await create_timer(1.8).timeout
	app.matching=true;app.lobby_status.set_queue({"state":"waiting","waited":27})
	for dims in [Vector2i(320,740),Vector2i(390,844),Vector2i(844,390)]:
		root.size=dims;await wait_layout()
		check(assist.footer.visible and assist.ready_action.visible,"ready action retained "+str(dims))
		check(app.get_viewport_rect().encloses(nav.bar.get_global_rect()),"queue plus setup footer fits "+str(dims))
		check(not assist.footer.get_global_rect().intersects(nav.bar.get_global_rect()),"queue ready and navigation do not overlap "+str(dims))
		await tap(nav.history_button);check(nav._history_target().get_global_rect().intersects(app.page_scroll.get_global_rect()),"record usable while queued in setup "+str(dims))
		await tap(nav.board_button);await shot("queue-setup-%d" % dims.x)
	app.matching=false;app.lobby_status.set_queue({})
	for dims in [Vector2i(1120,760),Vector2i(1440,900)]:
		root.size=dims;await wait_layout();check(not nav.bar.visible,"desktop footer stays hidden "+str(dims))
	print("MOBILE_NAV_CHECKS=",checks," FAILURES=",failures.size())
	var f=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close()
	quit(1 if not failures.is_empty() else 0)
