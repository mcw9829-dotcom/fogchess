extends RefCounted

func run(app: Control, tree: SceneTree, check: Callable) -> void:
	var feature = app.community
	var source: String = app.api.base_url
	var key: String = str(app.prefs.get_value(source,"patchnotes_seen",""))
	var data = {"version":"1.52","entries":[{"version":"v1.52","date":"2026-10-22","title":"Godot 웹 버전 공개","items":[{"tag":"UI","text":"보드에 집중하기 좋은 대국 화면과 기물 행동 아이콘."},{"tag":"추가","text":"방 코드로 관전하고, 종료한 대국을 리플레이로 확인하세요."}]}]}
	app.prefs.set_value(source,"patchnotes_seen","")
	app._navigation_home()
	var dialog = app._small_window("먼저 열어 둔 안내")
	feature.queue_update(data)
	check.call(app.find_child("UpdateNotice",true,false)==null,"updates do not replace an existing dialog or intro")
	check.call(str(app.prefs.get_value(source,"patchnotes_seen",""))=="","deferred updates are not marked as read")
	dialog[0].queue_free()
	await tree.process_frame
	app.room = "RECONNECT"
	check.call(not feature.show_pending_update(),"updates do not interrupt a reconnected game")
	app.room = ""
	app._friend_menu()
	check.call(not feature.show_pending_update(),"updates do not interrupt invitation forms")
	app._navigation_home()
	check.call(feature.show_pending_update(),"pending update appears after returning to the lobby")
	var notice: Window = app.find_child("UpdateNotice",true,false)
	check.call(notice!=null and notice.visible,"new update displays a visible announcement")
	check.call(app.rail_version.text=="v1.52 · 패치노트","version badge comes from the server")
	notice.queue_free()
	await tree.process_frame
	feature.queue_update(data)
	check.call(app.find_child("UpdateNotice",true,false)==null,"the same update is shown only once")
	data.entries[0].items[0].text = "새로 변경한 안내"
	feature.queue_update(data)
	notice = app.find_child("UpdateNotice",true,false)
	check.call(notice!=null,"changed release content produces a new notice")
	tree.root.size = Vector2i(390,844)
	await tree.process_frame
	app._layout()
	await tree.process_frame
	check.call(notice.size.x<=366,"announcement fits a narrow mobile viewport")
	var dismiss: Button = notice.find_child("UpdateDismiss",true,false)
	check.call(dismiss.get_global_rect().end.y<=notice.size.y,"announcement dismiss stays visible without scrolling on mobile")
	notice.queue_free()
	await tree.process_frame
	tree.root.size = Vector2i(1280,720)
	feature.queue_update({"entries":[]})
	check.call(app.find_child("UpdateNotice",true,false)==null,"empty patch notes never create a blank popup")
	app.prefs.set_value(source,"patchnotes_seen",key)
	await tree.process_frame
