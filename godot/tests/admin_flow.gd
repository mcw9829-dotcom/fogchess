extends RefCounted
func run(app: Control,tree: SceneTree,check: Callable) -> void:
	app._admin()
	var panel
	for node in app.find_children("*","VBoxContainer",true,false):
		if node.get_script()==preload("res://admin(관리자 화면).gd"): panel=node
	check.call(panel!=null,"native admin dialog opens")
	await panel.submit_login("invalid-test-key")
	check.call(panel.key.is_empty(),"invalid key stays at login")
	check.call(panel.error_label.text.contains("키가 일치하지"),"invalid key is not reported as a server outage")
	check.call(panel.error_text({"network_error":true}).contains("연결하지 못"),"network failure has a separate message")
	var login_field: LineEdit = panel.find_child("AdminKeyInput",true,false)
	var reveal: Button = panel.find_child("AdminKeyReveal",true,false)
	login_field.text = OS.get_environment("FOG_TEST_ADMIN_KEY")
	check.call(login_field.secret,"key is hidden by default")
	reveal.button_pressed = true
	check.call(not login_field.secret and reveal.text=="숨기기","operator can inspect entered key")
	reveal.button_pressed = false
	check.call(login_field.secret,"key visibility can be restored")
	# Exercise the real form callback instead of calling submit_login directly.
	var submit: Button = panel.find_children("*","Button",true,false).filter(func(b): return b.text=="관리자 로그인")[0]
	submit.pressed.emit()
	var deadline = Time.get_ticks_msec()+4000
	while panel.busy and Time.get_ticks_msec()<deadline: await tree.process_frame
	check.call(not panel.key.is_empty() and panel.response.has("counts"),"authenticated overview from server")
	await panel.switch_tab("users")
	check.call(panel.users.size()>0,"account list loaded")
	await panel.switch_tab("tickets")
	var target: Dictionary = {}
	for row in panel.rows:
		if row.message=="Godot admin fixture": target=row
	check.call(not target.is_empty(),"real feedback fixture loaded")
	if not target.is_empty():
		await panel.mutate("/admin/ops/ticket",{"id":int(target.id),"revision":int(target.revision),"state":"done","priority":"high","category":"bug","note":"Native verification complete"})
		var marked = false
		for row in panel.rows:
			if row.id==target.id: marked=row.state=="done"
		check.call(marked,"versioned feedback processing succeeds")
		await panel.switch_tab("audit")
		check.call(panel.rows.any(func(row): return row.action=="ticket"),"audit records feedback mutation")
	for tab in ["overview","users","tickets","games","notices","balance","audit"]:
		await panel.switch_tab(tab)
		await tree.create_timer(.25).timeout
		check.call(panel.tab==tab and panel.response.get("ok",false),"admin tab "+tab+" renders")
		if "--admin-capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			tree.root.get_texture().get_image().save_png(OS.get_environment("FOG_ADMIN_CAPTURE")+"/"+tab+"-dark.png")
	await panel.switch_tab("users")
	var user = panel.rows[0]
	panel.confirm_change("Native confirmation","sanction",{"userId":int(user.id),"kind":"warn","days":1,"reason":"QA confirmation cancelled"})
	await tree.process_frame
	var popup=panel.get_window().find_child("GameConfirmation",true,false)
	check.call(popup!=null,"moderation has styled confirmation")
	if popup!=null:
		popup.canceled.emit()
		await tree.process_frame
	var before = await panel.request("/admin/ops/audit")
	check.call(not before.rows.any(func(row): return row.reason=="QA confirmation cancelled"),"cancel does not mutate server")
	await panel.switch_tab("games")
	if not panel.rows.is_empty():
		var replay_id=str(panel.rows[0].get("replay_id",""))
		if not replay_id.is_empty():
			await panel.open_replay(replay_id)
			check.call(app.replay.active and app.replay.data.id==replay_id,"admin opens actual ended replay")
			await tree.create_timer(.2).timeout
			app.replay.close()
			await tree.process_frame
			app._admin()
			for node in app.find_children("*","VBoxContainer",true,false):
				if node.get_script()==preload("res://admin(관리자 화면).gd"): panel=node
			await panel.submit_login(OS.get_environment("FOG_TEST_ADMIN_KEY"))
	if "--admin-capture" in OS.get_cmdline_user_args():
		app.prefs.set_value("settings","light",true)
		app._apply_theme()
		await panel.switch_tab("notices")
		await tree.create_timer(.3).timeout
		RenderingServer.force_draw(false)
		tree.root.get_texture().get_image().save_png(OS.get_environment("FOG_ADMIN_CAPTURE")+"/notices-light.png")
	panel.refresh()
	panel.login()
	await tree.create_timer(.2).timeout
	check.call(panel.key.is_empty() and panel.rows.is_empty() and panel.users.is_empty(),"logout races cannot restore private data")
	panel.get_window().queue_free()
	await tree.process_frame
