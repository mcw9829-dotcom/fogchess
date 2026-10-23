extends SceneTree
const Design = preload("res://tooltip_design(공통 설명 카드 디자인).gd")
var app: Control
var failures := 0
var previous_pointer := Vector2.ZERO
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	if value: print("PASS: "+text)
	else: failures+=1; push_error(text)
func hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at-previous_pointer
	previous_pointer = at
	root.push_input(event,true)
	if at==Vector2(4,4):
		await create_timer(.25).timeout
		return
	# Capture the native popup when it appears, rather than after an arbitrary delay.
	for attempt in range(80):
		await create_timer(.03).timeout
		if native_tip(root)!=null:
			await process_frame
			await process_frame
			if native_tip(root)!=null: return
func native_tip(node: Node) -> PopupPanel:
	if node is PopupPanel and node.visible and node.theme_type_variation=="TooltipPanel": return node
	for child in node.get_children(true):
		var found := native_tip(child)
		if found!=null: return found
	return null
func verify_tip(at: Vector2, label: String) -> PopupPanel:
	var tip := native_tip(root)
	check(tip!=null,label+" opens a native tooltip")
	if tip==null: return null
	check(tip.get_theme_stylebox("panel").bg_color==Design.surface().bg_color,label+" shares the opaque card surface")
	var words: Label
	for child in tip.get_children():
		if child is Label: words=child
	check(words!=null and words.get_theme_font_size("font_size")==16,label+" uses 16px readable text")
	check(words!=null and words.get_theme_color("font_color")==Design.INK,label+" uses dark high-contrast ink")
	var rect := Rect2(Vector2(tip.position),Vector2(tip.size))
	check(not rect.grow(16).has_point(at),label+" keeps cursor clearance")
	check(absf(rect.get_center().x-at.x)<180 and minf(absf(rect.end.y-at.y),absf(rect.position.y-at.y))<65,label+" stays beside the hovered control")
	check(rect.position.x>=0 and rect.end.x<=root.size.x,label+" stays within viewport width")
	return tip
func verify_absent(label: String) -> PopupPanel:
	check(native_tip(root)==null,label+" shows no hover popup")
	return null
func capture(label: String, tip: PopupPanel) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://../.dev-data/unified-tooltip-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var picture := root.get_texture().get_image()
	picture.save_png(directory.path_join(label+".png"))
	if tip==null: return
	var rect := Rect2i(tip.position-Vector2i(12,12),tip.size+Vector2i(24,60)).intersection(Rect2i(Vector2i.ZERO,root.size))
	picture.get_region(rect).save_png(directory.path_join(label+"-detail.png"))
func guide_panel(node: Node) -> Control:
	if node is Control and node.tooltip_text.begins_with("마우스를 올리거나 클릭하면 시연"): return node
	for child in node.get_children():
		var found := guide_panel(child)
		if found!=null: return found
	return null
func verify_guide(label: String) -> void:
	app._help()
	await create_timer(.8).timeout
	var panel := guide_panel(app)
	check(panel!=null,label+" guide is present")
	if panel==null: return
	var window := panel.get_window()
	await hover(panel.get_global_rect().get_center()+Vector2(window.position))
	verify_absent(label+" guide card")
	await capture(label+"-guide-no-tooltip",null)
	window.queue_free()
	await create_timer(.3).timeout
	await hover(Vector2(4,4))
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.4).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	var mode: Control = app.mode_cards[0]
	await hover(mode.get_global_rect().get_center())
	verify_absent("home mode card")
	await capture("home-no-tooltip",null)
	await hover(Vector2(4,4))
	await verify_guide("home")
	app._settings()
	await create_timer(.4).timeout
	var toggle: Control = app.find_child("Setting_sound",true,false)
	var at: Vector2 = toggle.get_global_rect().get_center()
	await hover(at)
	var tip := verify_absent("setting switch")
	await capture("settings",tip)
	await hover(Vector2(4,4))
	check(native_tip(root)==null,"native hover dismissal is preserved")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await create_timer(.4).timeout
	at = toggle.get_global_rect().get_center()
	await hover(at)
	tip = verify_absent("light-theme switch")
	await capture("settings-light",tip)
	await hover(Vector2(4,4))
	# Enter the match screen: the shared service must now adopt native hints.
	app.subpage.hide()
	app.home.hide()
	app.game.show()
	app._layout()
	await verify_guide("in-match")
	# Dynamically created controls use the same native tooltip path without per-button scripts.
	var button: Button = app._button(app,"새 버튼",func(): pass)
	button.position = Vector2(360,400)
	button.size = Vector2(140,44)
	button.tooltip_text = "친구와 대국을 시작하려면 초대 링크를 복사해 전달하세요. 양쪽 모두 준비를 완료하면 현재 배치로 게임을 시작합니다."
	await create_timer(.2).timeout
	at=button.get_global_rect().get_center()
	await hover(at)
	tip=verify_tip(at,"dynamic long description")
	if tip!=null: check(tip.size.x<=310,"long description wraps within a bounded card")
	await capture("long-description",tip)
	await hover(Vector2(4,4))
	button.queue_free()
	var pair: Array = app._window("팝업 툴팁 검증")
	var inside: Button = app._button(pair[1],"초대 링크",func(): pass)
	inside.tooltip_text = "친구에게 전달할 초대 링크를 복사합니다."
	await create_timer(.8).timeout
	var local_at: Vector2 = inside.get_global_rect().get_center()
	var event := InputEventMouseMotion.new()
	event.position = local_at
	event.global_position = local_at
	await hover(local_at+Vector2(pair[0].position))
	if native_tip(root)==null:
		pair[0].push_input(event,true)
		await create_timer(1.4).timeout
	tip = native_tip(root)
	check(tip!=null,"embedded dialog tooltip opens through the shared service")
	if tip!=null:
		check(tip.get_theme_stylebox("panel").bg_color==Design.surface().bg_color,"embedded dialog shares the card surface")
		check(tip.size.x<=310,"embedded dialog long hint remains bounded")
		var embedded_at: Vector2 = local_at+Vector2(pair[0].position)
		check(not Rect2(Vector2(tip.position),Vector2(tip.size)).grow(16).has_point(embedded_at),"embedded dialog preserves cursor clearance in the embedding viewport")
		var rect := Rect2(Vector2(tip.position),Vector2(tip.size))
		check(absf(rect.get_center().x-embedded_at.x)<180 and minf(absf(rect.end.y-embedded_at.y),absf(rect.position.y-embedded_at.y))<65,"embedded dialog tooltip stays beside its button")
		await capture("dialog",tip)
	pair[0].queue_free()
	await create_timer(.2).timeout
	root.size = Vector2i(320,844)
	app._layout()
	await create_timer(.4).timeout
	button = app._button(app,"화면 경계",func(): pass)
	button.position = Vector2(180,5)
	button.size = Vector2(130,44)
	button.tooltip_text = "내 진영 3줄 안에서 기물과 놓을 칸을 차례로 선택해 배치를 바꿀 수 있습니다."
	await create_timer(.2).timeout
	at=button.get_global_rect().get_center()
	await hover(at)
	tip=verify_tip(at,"mobile top edge")
	await capture("mobile-top",tip)
	await hover(Vector2(4,4))
	button.queue_free()
	root.size = Vector2i(1280,900)
	app._settings()
	app._layout()
	await create_timer(.4).timeout
	toggle = app.find_child("Setting_sound",true,false)
	await hover(toggle.get_global_rect().get_center())
	tip = verify_absent("settings after leaving the match")
	await capture("settings-after-match",tip)
	app.queue_free()
	await process_frame
	print("UNIFIED_TOOLTIP_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
