extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app
var pending_update: Dictionary = {}
var update_server := ""
var update_timer: Timer

func _init(context: Control) -> void:
	app = context

func check_updates() -> void:
	var source: String = app.api.base_url
	var data: Dictionary = await app.api.request("/patchnotes")
	# An optional announcement must never block sign-in, joining, or playing.
	if source!=app.api.base_url or data.get("network_error") or data.get("ok",true)==false: return
	queue_update(data)

func _update_key(data: Dictionary) -> String:
	var entries: Array = data.get("entries",[])
	if entries.is_empty(): return ""
	return str(data.get("revision",JSON.stringify(entries[0]).sha256_text()))

func queue_update(data: Dictionary) -> void:
	_stop_update_timer()
	pending_update = data.duplicate(true)
	update_server = app.api.base_url
	var version: String = str(data.get("version",""))
	if not version.is_empty(): app.rail_version.text = "v"+version+" · 패치노트"
	if show_pending_update(): return
	update_timer = Timer.new()
	update_timer.wait_time = 1.0
	update_timer.timeout.connect(show_pending_update)
	app.add_child(update_timer)
	update_timer.start()

func _stop_update_timer() -> void:
	if is_instance_valid(update_timer):
		update_timer.stop()
		update_timer.queue_free()
	update_timer = null

func show_pending_update() -> bool:
	var key := _update_key(pending_update)
	if update_server!=app.api.base_url or key.is_empty() or str(app.prefs.get_value(update_server,"patchnotes_seen",""))==key:
		pending_update = {}
		_stop_update_timer()
		return true
	# Keep reconnects, invitation forms, tutorials, and existing dialogs uninterrupted.
	if not app.room.is_empty() or app.busy or app.matching or app.replay.active or not app.home.visible or app.subpage.visible: return false
	for child in app.get_children():
		if child is Window and child.visible: return false
	var entry: Dictionary = pending_update.entries[0]
	var pair = app._small_window("새 업데이트",600,580)
	pair[0].name = "UpdateNotice"
	# Keep dismiss/details reachable even when the release text needs scrolling.
	var scroll: ScrollContainer = pair[1].get_parent()
	var panel: PanelContainer = scroll.get_parent()
	panel.remove_child(scroll)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation",12)
	panel.add_child(layout)
	var header: HBoxContainer = pair[1].get_child(0)
	pair[1].remove_child(header)
	layout.add_child(header)
	layout.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app._label(pair[1],"%s  ·  %s" % [entry.get("version",""),entry.get("date","")],12)
	var heading = app._label(pair[1],str(entry.get("title","")),24)
	heading.add_theme_font_override("font",app._original_font(700))
	app._label(pair[1],"이번 업데이트에서 달라진 내용을 확인하세요.",13)
	var items: Array = entry.get("items",[])
	for index in range(mini(items.size(),4)):
		var item: Dictionary = items[index]
		var card = app._card(pair[1],"")
		app._label(card,str(item.get("tag","업데이트")),11)
		app._label(card,str(item.get("text","")),14)
	if items.size()>4: app._label(pair[1],"외 %d개 변경 사항은 전체 패치노트에서 확인할 수 있어요." % (items.size()-4),12)
	var actions = HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_END
	layout.add_child(HSeparator.new())
	layout.add_child(actions)
	app._button(actions,"전체 패치노트",func(): pair[0].hide(); pair[0].queue_free(); await _patchnotes())
	var dismiss = app._button(actions,"확인 · 플레이하기",pair[0].queue_free,"primary")
	dismiss.name = "UpdateDismiss"
	dismiss.grab_focus()
	app._label(layout,"같은 업데이트는 다시 띄우지 않아요. 패치노트에서 언제든 다시 볼 수 있어요.",11)
	app.prefs.set_value(update_server,"patchnotes_seen",key)
	app._save()
	pending_update = {}
	_stop_update_timer()
	return true

func _leaderboard() -> void:
	var data: Dictionary = await app.api.request("/leaderboard")
	if not app._report(data): return
	var pair = app._small_window("리더보드",460,680)
	pair[0].size = Vector2i(mini(int(app.size.x)-24,460),mini(int(app.size.y)-24,680))
	pair[0].position = (app.get_viewport_rect().size-Vector2(pair[0].size))/2
	app._label(pair[1],"티어 사다리",14)
	var ladder = GridContainer.new()
	ladder.columns = 3 if pair[0].size.x<440 else 6
	ladder.add_theme_constant_override("h_separation",4)
	ladder.add_theme_constant_override("v_separation",4)
	pair[1].add_child(ladder)
	var tiers: Array = data.get("rules",{}).get("tiers",[[0,"P"],[1000,"N"],[1200,"R"],[1500,"B"],[1700,"Q"],[1900,"K"]])
	tiers.sort_custom(func(a,b): return int(a[0])>int(b[0]))
	for index in range(tiers.size()):
		var tier: Array = tiers[index]
		var cell = PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style: StyleBoxFlat = app.theme.get_stylebox("panel","PanelContainer").duplicate()
		style.set_corner_radius_all(6)
		for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,5.0)
		cell.add_theme_stylebox_override("panel",style)
		ladder.add_child(cell)
		var card = VBoxContainer.new()
		card.custom_minimum_size.x = 49
		cell.add_child(card)
		var icon = TextureRect.new()
		icon.texture = load("res://pieces/Chess_%slt45.svg" % str(tier[1]).to_lower())
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(28,28)
		card.add_child(icon)
		var label = app._label(card,app.NAMES.get(tier[1],tier[1]),11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var threshold = "%d+" % int(tier[0]) if index==0 else "%d~%d" % [int(tier[0]),int(tiers[index-1][0])-1]
		label = app._label(card,threshold,9)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rules_button = app._button(pair[1],"레이팅 규칙 보기",func(): pass)
	rules_button.name = "RatingRulesOpen"
	rules_button.pressed.connect(func(): preload("res://features/rating_rules(레이팅 안내 팝업).gd").new(app).show_rules(data.get("rules",{}),pair[0],rules_button))

	app._label(pair[1],"순위 · 레이팅 순 상위 50명",14)
	_rank_table(pair[1],data.get("rows",[]))

func _rank_table(parent: Node, players: Array) -> void:
	var grid = GridContainer.new()
	grid.name = "LeaderboardGrid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation",0)
	grid.add_theme_constant_override("v_separation",0)
	parent.add_child(grid)
	for column in range(5):
		_rank_cell(grid,["순위","티어","플레이어","전적","레이팅"][column],column,-1)
	for index in range(players.size()):
		var player: Dictionary = players[index]
		var values = [str(index+1),str(player.get("tier","P")),str(player.get("name","")),"%d승 %d패" % [int(player.get("wins",0)),int(player.get("losses",0))],str(int(player.get("rating",0)))]
		for column in range(5): _rank_cell(grid,values[column],column,index)
	if players.is_empty(): app._label(parent,"아직 등록된 순위가 없습니다. 첫 대국을 시작해 보세요.",13)

func _rank_cell(grid: GridContainer, value: String, column: int, row: int) -> void:
	var colors: Dictionary = app.ui_components._palette()
	var cell = PanelContainer.new()
	cell.custom_minimum_size = Vector2([36,40,64,76,60][column],34 if row<0 else 42)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if column==2 else Control.SIZE_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = colors.button if row<0 else (colors.surface.lerp(colors.button,.35) if row%2==1 else colors.surface)
	style.border_color = colors.border
	style.border_width_left = 1 if column==0 else 0
	style.border_width_right = 1
	style.border_width_top = 1 if row<0 else 0
	style.border_width_bottom = 1
	style.content_margin_left = 6
	style.content_margin_right = 6
	cell.add_theme_stylebox_override("panel",style)
	grid.add_child(cell)
	if column==1 and row>=0:
		var icon = TextureRect.new()
		icon.texture = load("res://pieces/Chess_%slt45.svg" % value.to_lower())
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(24,24)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.tooltip_text = app.NAMES.get(value,value)
		cell.add_child(icon)
	else:
		var label = app._label(cell,value,12 if row<0 or column==3 else 14)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column==2 else HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = value
		if row<0: label.add_theme_font_override("font",app._original_font(700))

func _history() -> void:
	var pair = app._small_window("최근 전적",380,520)
	app._profile_history(pair[1])

func _patchnotes() -> void:
	var data: Dictionary = await app.api.request("/patchnotes")
	if not app._report(data): return
	var pair = app._small_window("서버 패치노트",680,650)
	app._label(pair[1],"현재 v"+str(data.get("version","")),12)
	var entries: Array = data.get("entries",[])
	if entries.is_empty(): app._label(pair[1],"패치노트가 없어요.",13)
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var card = app._card(pair[1],"")
		var heading = app._button(card,"",func(): pass)
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var body = VBoxContainer.new()
		card.add_child(body)
		body.visible = index<3
		var update = func(): heading.text = ("▾ " if body.visible else "▸ ")+"%s · %s   %s" % [entry.get("version",""),entry.get("date",""),entry.get("title","")]
		update.call()
		heading.pressed.connect(func(): body.visible = not body.visible; update.call())
		for item in entry.get("items",[]):
			var row = HBoxContainer.new()
			body.add_child(row)
			var badge = app._label(row,str(item.get("tag","")),11)
			badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			badge.custom_minimum_size.x = 34
			badge.modulate = {"신규":Color("8bbf92"),"개선":Color("98b9d2"),"수정":Color("d69a8f"),"밸런스":Color("d5b97c")}.get(item.get("tag"),Color("b3a999"))
			var text = app._label(row,str(item.get("text","")),12)
			if item.get("tag") in ["기술","개발"]: text.modulate = Color("958c82")

func _feedback() -> void:
	var pair = app._small_window("개발자에게 피드백",440,440)
	pair[0].set_meta("suppress_hover_tooltips",true)
	var form = VBoxContainer.new()
	pair[1].add_child(form)
	app._label(form,"버그·밸런스·아이디어 뭐든 좋아요. 로그인 상태면 닉네임이 함께 전달되고, 아니면 익명입니다.",12)
	var category = OptionButton.new()
	for text in ["버그 · 이상 동작","밸런스 · 규칙","제안 · 아이디어","기타"]: category.add_item(text)
	category.custom_minimum_size.y = 40
	form.add_child(category)
	var content = TextEdit.new()
	content.placeholder_text = "어떤 상황에서 무엇이 있었는지 적어주세요 (최대 1000자)"
	content.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.custom_minimum_size.y = 130
	form.add_child(content)
	for state in ["normal","focus","read_only"]:
		var style: StyleBox = app.theme.get_stylebox("focus" if state=="focus" else "normal","LineEdit").duplicate()
		content.add_theme_stylebox_override(state,style)
	var counter = app._label(form,"0 / 1000",11)
	content.text_changed.connect(func():
		if content.text.length()>1000:
			content.text = content.text.left(1000)
			content.set_caret_line(content.get_line_count()-1)
			content.set_caret_column(content.get_line(content.get_line_count()-1).length())
		counter.text = "%d / 1000" % content.text.length())
	var error = app._label(form,"",12)
	error.set_meta("form_error",true)
	var send = app._form_action(form,"보내기","답장은 없지만 꼭 읽습니다","chat")
	send.pressed.connect(func():
		error.text = ""
		var message = content.text.strip_edges()
		if message.length()<3: error.text = "내용을 조금 더 적어주세요(3자 이상)."; content.grab_focus(); return
		send.disabled = true
		var data: Dictionary = await app.api.request("/feedback",{"category":["bug","balance","idea","other"][category.selected],"message":message,"session":app.session,"name":str(app.me.get("name",app.guest_field.text)),"room":app.room,"ua":"Godot client"})
		if not is_instance_valid(send): return
		send.disabled = false
		if not data.get("ok"): error.text = str(data.get("msg","보내지 못했어요. 잠시 후 다시 시도해 주세요.")); return
		content.text = ""
		form.hide()
		app._label(pair[1],"보냈어요. 고마워요!",20)
		await app.get_tree().create_timer(1.8).timeout
		if is_instance_valid(pair[0]): pair[0].queue_free())
	content.grab_focus()

func _load_home_ranks() -> void:
	var data: Dictionary = await app.api.request("/leaderboard")
	var rows: VBoxContainer = app.ranking.get_node("Ranks")
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var players: Array = data.get("rows",[])
	app.ranking_subtitle.text = "상위 %d명 · 전체 %d명" % [mini(10,players.size()),int(data.get("total",players.size()))]
	if players.is_empty():
		app._label(rows,"아직 등록된 순위가 없습니다.\n첫 대국을 시작해 보세요." if not data.get("network_error") else "순위를 불러올 수 없습니다.\n서버 연결을 확인해 주세요.",13)
	for index in range(mini(10,players.size())): app._rank_row(rows,players[index],index)

func _rank_row(parent: Node, player: Dictionary, index: int) -> void:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1,1,1,.035) if index%2==1 else Color(0,0,0,0)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	panel.add_child(row)
	var number = app._label(row,str(index+1),13)
	number.custom_minimum_size.x = 24
	number.size_flags_horizontal = Control.SIZE_FILL
	var icon = TextureRect.new()
	icon.texture = load("res://pieces/Chess_%slt45.svg" % str(player.get("tier","P")).to_lower())
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(22,22)
	row.add_child(icon)
	var name_label = app._label(row,str(player.get("name","")),13)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var record = app._label(row,"%d승 %d패" % [int(player.get("wins",0)),int(player.get("losses",0))],11)
	record.size_flags_horizontal = Control.SIZE_FILL
	record.autowrap_mode = TextServer.AUTOWRAP_OFF
	var rating = app._label(row,str(int(player.get("rating",0))),14)
	rating.autowrap_mode = TextServer.AUTOWRAP_OFF
	rating.custom_minimum_size.x = 40
	rating.size_flags_horizontal = Control.SIZE_FILL
	rating.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _tier(rating: int) -> String:
	for entry in [[1900,"K"],[1700,"Q"],[1500,"B"],[1200,"R"],[1000,"N"]]:
		if rating>=entry[0]: return entry[1]
	return "P"

func _admin() -> void:
	var pair = app._small_window("안개전장 체스 · 관리자",920,680)
	var panel = preload("res://admin(관리자 화면).gd").new()
	panel.app = app
	pair[1].add_child(panel)
	pair[0].visibility_changed.connect(func():
		if not pair[0].visible: panel.key=""; pair[0].queue_free())
