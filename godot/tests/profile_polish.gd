extends SceneTree
var app
var checks:=0
var failures:=0
func _initialize():run.call_deferred()
func check(ok:bool,text:String):
	checks+=1
	if ok:print("PASS: "+text)
	else:failures+=1;push_error(text)
func settle(t:float=.35):
	app._layout();await create_timer(t).timeout
func shot(name:String):
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func win() -> Window:
	for c in app.get_children():
		if c is Window and c.visible and not c.is_queued_for_deletion():return c
	return null
func tagged(parent:Node,key:String,value:Variant=true) -> Node:
	for node in parent.find_children("*","",true,false):
		if node.has_meta(key) and node.get_meta(key)==value:return node
	return null
func button(text:String) -> Button:
	for b in win().find_children("*","Button",true,false):
		if b.text==text and b.is_visible_in_tree():return b
	return null
func error_text() -> String:
	var out:=""
	for label in win().find_children("*","Label",true,false):
		if label.get_meta("form_error",false):out+=label.text
	return out
func close():
	for c in app.get_children():
		if c is Window:c.hide();c.queue_free()
	await process_frame
func click(control:Control):
	var point:Vector2=Vector2(control.get_window().position)+control.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
		root.push_input(event,true);await process_frame
	await create_timer(.22).timeout
func run():
	root.size=Vector2i(1280,900);app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await create_timer(.4).timeout
	for c in app.get_children():
		if c is Timer:c.stop()
	app.audio.enabled=false
	var fixture:Dictionary=await app.api.request("/test-profile",{"count":20})
	check(fixture.get("ok",false),"temporary profile fixture exists")
	if not fixture.get("ok",false):quit(2);return
	app.session=fixture.session;app.me=fixture.user;app._update_account()
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		app._account();await settle(.7)
		var window:=win();var ui=window.get_meta("profile_controller")
		check(window.find_children("*","ScrollContainer",true,false).size()==1,"profile uses only one scroll container")
		for dims in [Vector2i(1280,900),Vector2i(390,844),Vector2i(320,740),Vector2i(844,390)]:
			root.size=dims;await settle(.3)
			for tab in range(3):
				await click(ui.tab_buttons[tab]);await settle(.2)
				check(ui.current_tab==tab,"real input selects tab "+str([dims,light,tab]))
				check(window.size.x<=dims.x-24 and window.position.x>=0 and window.position.y>=0,"profile window fits "+str([dims,light,tab]))
				var inside:=true
				for control in window.find_children("*","Control",true,false):
					if control.is_visible_in_tree() and control is Button:
						inside=inside and control.size.y>=44 and control.get_global_rect().position.x>=-1 and control.get_global_rect().end.x<=window.size.x+1
				check(inside,"buttons fit and keep 44px targets "+str([dims,light,tab]))
				if tab==1:
					var history_readable:=true
					for row in window.find_children("*","",true,false):
						if not row.has_meta("profile_history_row"):continue
						var heading:HBoxContainer=row.get_child(0)
						history_readable=history_readable and heading.get_child(0).size.y<30 and heading.get_child(2).size.y<30 and heading.get_global_rect().end.x<=window.size.x
					check(history_readable,"history outcome and rating remain single line "+str([dims,light]))
				ui.body_scroll.scroll_vertical=int(ui.body_scroll.get_v_scroll_bar().max_value);await process_frame
				check(ui.tab_buttons.all(func(b):return b.get_global_rect().position.y>=0 and b.get_global_rect().end.y<window.size.y),"tabs remain visible while body scrolls "+str([dims,light,tab]))
				ui.body_scroll.scroll_vertical=0;await create_timer(.15).timeout
				if dims.x in [1280,390]:shot(("desktop" if dims.x>400 else "mobile")+"-"+("light" if light else "dark")+"-"+["summary","history","manage"][tab])
				if dims.x==320 and tab==2:shot("narrow-management-"+("light" if light else "dark"))
				if dims.x==844 and tab==2:shot("landscape-management-"+("light" if light else "dark"))
		await close()
	# Pagination preserves all 20 records without another nested scroll.
	root.size=Vector2i(390,844);app._account();await settle(.6)
	var ui=win().get_meta("profile_controller");ui.select_tab(1);await settle()
	var history=tagged(win(),"profile_history")
	check(history.get_meta("profile_history_count")==20,"twenty saved matches are available")
	var visited:Array=[]
	for page in range(4):
		var rows:Array=[]
		for node in win().find_children("*","",true,false):
			if node.has_meta("profile_history_row"):rows.append(node.get_meta("profile_history_row"))
		check(rows.size()==5,"history page contains five records "+str(page))
		visited.append_array(rows)
		if page<3:tagged(win(),"profile_action","history_next").pressed.emit();await settle()
	check(visited==range(20),"pagination covers twenty records exactly once")
	check(tagged(win(),"profile_action","history_next").disabled,"last page disables next")
	ui.select_tab(0);await settle()
	var trend=tagged(win(),"profile_trend")
	check(trend!=null and trend.rows.size()==10,"summary uses last ten rated games")
	# Keep both the long name and expanded tier list readable at 320px.
	root.size=Vector2i(320,740);ui.display_name.text="안개전장테스트플레이어";await settle()
	tagged(win(),"profile_action","tiers").pressed.emit();await settle()
	check(ui.display_name.get_global_rect().end.x<=win().size.x,"long display name remains inside popup")
	ui.select_tab(2);await settle()
	tagged(win(),"profile_action","name").pressed.emit();await settle()
	var fields=win().find_children("*","LineEdit",true,false)
	fields[0].text="!";button("저장").pressed.emit();await settle()
	check("닉네임은" in error_text(),"invalid nickname is rejected in form")
	fields[0].text="RefinedUser";button("저장").pressed.emit();await settle(.6)
	check(app.me.name=="RefinedUser" and ui.display_name.text=="RefinedUser","nickname updates server and summary")
	check(ui.manage_actions.visible and not ui.form_host.visible,"saved form returns to aligned management actions")
	tagged(win(),"profile_action","pw").pressed.emit();await settle()
	fields=win().find_children("*","LineEdit",true,false)
	fields[0].text="ProfilePass123!";fields[1].text="ChangedProfile123!";fields[2].text="Mismatch123!"
	button("변경").pressed.emit();await settle()
	check("일치하지" in error_text(),"password mismatch is blocked")
	fields[2].text="ChangedProfile123!";button("변경").pressed.emit();await settle(.6)
	check(ui.manage_actions.visible and not ui.form_host.visible,"password change returns to management")
	tagged(win(),"profile_action","name").pressed.emit();await settle();button("취소").pressed.emit();await settle()
	check(ui.manage_actions.visible and not ui.form_host.visible,"cancel returns to management without empty gap")
	tagged(win(),"profile_action","recov").pressed.emit();await settle()
	fields=win().find_children("*","LineEdit",true,false);fields[0].text="ChangedProfile123!"
	tagged(win(),"profile_action","form_submit").pressed.emit();await settle(.6)
	check(win().title=="복구 코드 보관","recovery returns one-time code dialog")
	button("보관했어요").pressed.emit();await settle(.6)
	check(win().has_meta("profile_controller"),"recovery completion returns to profile")
	ui=win().get_meta("profile_controller");ui.select_tab(2);await settle()
	tagged(win(),"profile_action","delete").pressed.emit();await settle()
	check(win().title=="계정 삭제" and button("계정 영구 삭제").disabled,"delete action retains password and consent gate")
	button("취소").pressed.emit();await settle()
	check(not app.session.is_empty(),"cancel deletion preserves account")
	await close();app._account();await settle(.5);ui=win().get_meta("profile_controller");ui.select_tab(2);await settle()
	tagged(win(),"profile_action","logout").pressed.emit();await settle(.5)
	check(app.session.is_empty() and app.me.is_empty(),"logout still clears authenticated account")
	# Empty and failed requests have explicit states and working retry.
	fixture=await app.api.request("/test-profile",{"count":0});app.session=fixture.session;app.me=fixture.user;app._account();await settle(.5)
	ui=win().get_meta("profile_controller");ui.select_tab(1);await settle()
	check(tagged(win(),"profile_history").get_meta("profile_history_state")=="empty","empty history has a dedicated message")
	shot("empty-history");await close()
	await app.api.request("/test-history-mode",{"fail":true});app._account();await settle(.5)
	ui=win().get_meta("profile_controller");ui.select_tab(1);await settle()
	check(tagged(win(),"profile_action","history_retry")!=null,"failed history exposes retry")
	await app.api.request("/test-history-mode",{"fail":false})
	tagged(win(),"profile_action","history_retry").pressed.emit();await settle(.5)
	check(tagged(win(),"profile_history").get_meta("profile_history_state")=="empty","history retry reaches server and recovers")
	await close();app.me.weakPw=true;app._account();await settle(.5)
	ui=win().get_meta("profile_controller")
	check(ui.current_tab==2 and ui.form_host.visible and ui.warning.visible,"legacy password guidance opens correct management form")
	await close()
	print("PROFILE_UI_CHECKS=",checks);print("FAILURES=",failures)
	app.queue_free();await process_frame;quit(1 if failures else 0)
