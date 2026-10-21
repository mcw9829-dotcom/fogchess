extends RefCounted
func run(app: Control,tree: SceneTree,check: Callable) -> void:
	app._open_invitation("ab12")
	var fields: Array = app.subpage.find_children("*","LineEdit",true,false)
	check.call(fields.size()>0 and fields[0].text=="AB12","invitation fills visible room field")
	app._navigation_home()
	app._admin()
	var panel: VBoxContainer
	for node in app.find_children("*","VBoxContainer",true,false):
		if node.get_script()==preload("res://admin(관리자 화면).gd"): panel=node
	check.call(panel!=null,"native admin dialog opens")
	await panel.submit_login("invalid-test-key")
	check.call(panel.key.is_empty() and "비밀번호" in panel.error_label.text,"invalid admin key stays at login")
	await panel.submit_login(OS.get_environment("FOG_TEST_ADMIN_KEY"))
	check.call(not panel.key.is_empty() and panel.users.size()>0 and panel.rows.size()>0,"admin authenticated users and feedback loaded")
	var target: Dictionary={}
	for row in panel.rows:
		if row.message=="Godot admin fixture": target=row
	check.call(not target.is_empty(),"admin fixture comes from real API")
	if not target.is_empty():
		await panel.mutate("/feedback/done",{"id":target.id,"done":true})
		var marked := false
		for row in panel.rows:
			if row.id==target.id: marked=bool(row.done)
		check.call(marked,"admin marks feedback as processed")
		panel.show_done=true; panel.render()
		if "--capture" in OS.get_cmdline_user_args():
			await tree.create_timer(.2).timeout
			RenderingServer.force_draw(false)
			tree.root.get_texture().get_image().save_png("res://tests/admin.png")
		await panel.mutate("/feedback/done",{"id":target.id,"done":false})
		var reopened := false
		for row in panel.rows:
			if row.id==target.id: reopened=not bool(row.done)
		check.call(reopened,"admin reopens processed feedback")
		panel.confirm_delete(int(target.id))
		await tree.process_frame
		var confirmation: ConfirmationDialog
		for child in panel.get_window().get_children():
			if child is ConfirmationDialog: confirmation=child
		check.call(confirmation!=null and "되돌릴 수" in confirmation.dialog_text,"feedback deletion requires confirmation")
		confirmation.canceled.emit()
		await tree.process_frame
		check.call(panel.rows.any(func(row): return row.id==target.id),"cancelled delete keeps feedback")
		panel.confirm_delete(int(target.id))
		await tree.process_frame
		for child in panel.get_window().get_children():
			if child is ConfirmationDialog: child.confirmed.emit()
		for i in range(100):
			if not panel.busy: break
			await tree.create_timer(.05).timeout
		check.call(not panel.rows.any(func(row): return row.id==target.id),"confirmed API deletion removes only fixture feedback")
	panel.refresh()
	panel.login()
	await tree.create_timer(.2).timeout
	check.call(panel.key.is_empty() and panel.rows.is_empty() and panel.users.is_empty(),"admin logout clears credentials and private data")
	panel.get_window().queue_free()
	await tree.process_frame
