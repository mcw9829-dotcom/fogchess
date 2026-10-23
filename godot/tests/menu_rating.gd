extends SceneTree
var app: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error(message)
func capture(label: String) -> void:
	await create_timer(.35).timeout
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := ProjectSettings.globalize_path("res://../.dev-data/menu-rating-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func open_rules() -> Window:
	var trigger: Button = app.find_child("RatingRulesOpen",true,false)
	trigger.grab_focus()
	trigger.pressed.emit()
	await create_timer(.4).timeout
	return app.find_child("RatingRulesDialog",true,false)
func check_fit(window: Window, label: String) -> void:
	var scroll: ScrollContainer = window.find_child("RatingRulesScroll",true,false)
	check(window.size.x<=root.size.x-24,label+" dialog fits viewport")
	check(scroll.get_child(0).size.x<=scroll.size.x,label+" body has no horizontal overflow")
	var done: Button = window.find_child("RatingRulesDone",true,false)
	check(done.get_global_rect().end.y<=window.size.y,label+" confirmation remains inside window")
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	var Icon = preload("res://original_icon(원본 스타일 아이콘).gd")
	for key in ["rank","lobby","replay","watch","join","computer","practice","settings","book","trophy","chat","user","easy","normal","hard","accept","decline"]:
		var texture = load(Icon.asset_path(key))
		check(texture is Texture2D and texture.get_width()==96,key+" loads a reusable 96px SVG texture")
	check(Icon.asset_path("play")!=Icon.asset_path("replay"),"rank and replay use distinct assets")
	check(Icon.asset_path("people")!=Icon.asset_path("watch"),"lobby and spectating use distinct assets")
	await capture("menu-dark")
	for card in app.mode_cards:
		var content: Control = card.get_node("ModeCardContent")
		check(card.size.y>=content.get_combined_minimum_size().y,"mode card contains its wrapped description: "+str(card.get_meta("action_title")))
	await app._leaderboard()
	await create_timer(.3).timeout
	var trigger: Button = app.find_child("RatingRulesOpen",true,false)
	check(trigger!=null,"leaderboard exposes rating rules button")
	var leaderboard := trigger.get_window()
	var dialog := await open_rules()
	check(dialog!=null and dialog.visible and dialog.exclusive,"button opens an exclusive rating dialog")
	check(not leaderboard.visible,"leaderboard is hidden while rating dialog is active")
	var dimmed := false
	for child in app.get_children():
		if child is ColorRect and child.visible and child.color.a>.5: dimmed=true
	check(dimmed,"background is dimmed")
	check(dialog.find_child("StartingRating",true,false).text=="1000점","starting rating comes from server payload")
	check(dialog.find_child("RatingFloor",true,false).text=="500점","minimum rating comes from server payload")
	check(dialog.find_child("Delta_0_2",true,false).text=="+16","equal-rating victory example is correct")
	check(dialog.find_child("Delta_300_0",true,false).text=="-5","stronger-opponent defeat example is correct")
	check(dialog.find_child("BotCap_easy",true,false).text=="1500","bot cap uses server rating plus cap")
	check_fit(dialog,"desktop")
	await capture("rating-dark-top")
	var scroll: ScrollContainer = dialog.find_child("RatingRulesScroll",true,false)
	scroll.scroll_vertical = 2000
	await capture("rating-dark-bottom")
	var done: Button = dialog.find_child("RatingRulesDone",true,false)
	done.pressed.emit()
	await create_timer(.3).timeout
	check(leaderboard.visible and trigger.has_focus(),"confirmation returns to leaderboard and restores focus")
	dialog = await open_rules()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog.push_input(escape,true)
	await create_timer(.3).timeout
	check(not is_instance_valid(dialog) and leaderboard.visible,"Escape closes only the rules and returns to leaderboard")
	root.size = Vector2i(390,844)
	app._layout()
	await create_timer(.3).timeout
	dialog = await open_rules()
	check_fit(dialog,"390px")
	await capture("rating-mobile")
	root.size = Vector2i(320,740)
	app._layout()
	await create_timer(.3).timeout
	check_fit(dialog,"320px")
	await capture("rating-320")
	dialog.close_requested.emit()
	await create_timer(.3).timeout
	root.size = Vector2i(1280,900)
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	app._layout()
	dialog = await open_rules()
	check_fit(dialog,"light theme")
	await capture("rating-light")
	dialog.close_requested.emit()
	await create_timer(.3).timeout
	leaderboard.queue_free()
	await create_timer(.3).timeout
	await capture("menu-light")
	var alternate := {"default":1200,"floor":600,"k":40,"botRated":true,"botNoLoss":false,"bot":{"easy":1400,"normal":1600,"hard":1800}}
	dialog = preload("res://features/rating_rules(레이팅 안내 팝업).gd").new(app).show_rules(alternate)
	await create_timer(.3).timeout
	check(dialog.find_child("StartingRating",true,false).text=="1200점" and dialog.find_child("RatingFloor",true,false).text=="600점","alternate start and floor are not hardcoded")
	check(dialog.find_child("Delta_0_2",true,false).text=="+20","alternate K factor updates examples")
	check(dialog.find_child("BotCap_easy",true,false).text=="제한 없음","absent bot cap has an explicit unlimited state")
	check(dialog.find_child("BotRatingPolicy",true,false).text=="승리 시 상승 · 패배 시 하락","server bot-loss policy is respected")
	dialog.queue_free()
	await process_frame
	dialog = preload("res://features/rating_rules(레이팅 안내 팝업).gd").new(app).show_rules({"botRated":false})
	await process_frame
	check(dialog.find_child("BotRatingPolicy",true,false)==null,"unrated computer mode has no rated policy table")
	app.queue_free()
	await process_frame
	print("MENU_RATING_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
