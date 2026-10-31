extends RefCounted
## Profile-only layout. API and account mutations remain in account.gd.
var app
var account
var window: Window
var body_scroll: ScrollContainer
var pages: Array[Control] = []
var tab_buttons: Array[Button] = []
var display_name: Label
var manage_actions: VBoxContainer
var form_host: VBoxContainer
var status: Label
var warning: Control
var current_tab := 0

class ProfileTrend extends "res://rating_trend(최근 10판 레이팅).gd":
	func text_at(value: String, at: Vector2, width: float, font_size: int, color: Color, align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT) -> void:
		super.text_at(value,at,width,maxi(13,font_size),color,align)

func _init(context,feature) -> void:
	app = context
	account = feature

func _muted(parent: Node,text: String,font_size: int=14) -> Label:
	var label: Label = app._label(parent,text,font_size)
	label.add_theme_color_override("font_color",app.ui_components._palette().muted)
	return label

func _card(parent: Node,name: String="",dark: bool=false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var palette: Dictionary = app.ui_components._palette()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202b30") if dark else palette.button.lerp(palette.surface,.55)
	style.border_color = Color("#3a484f") if dark else palette.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(edge,14)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	if not name.is_empty():
		var label: Label = app._label(box,name,16)
		if dark: label.add_theme_color_override("font_color",Color("#f3eee4"))
	return box

func open() -> void:
	var pair: Array = app._small_window("내 프로필",680,740)
	window = pair[0]
	window.set_meta("profile_window",true)
	window.set_meta("profile_controller",self)
	var root: VBoxContainer = pair[1]
	# Keep title/tabs outside the only scrollable body, including on landscape phones.
	var outer_scroll: ScrollContainer = root.get_parent()
	var panel: PanelContainer = outer_scroll.get_parent()
	outer_scroll.remove_child(root)
	panel.remove_child(outer_scroll)
	outer_scroll.queue_free()
	panel.add_child(root)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation",12)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",6)
	root.add_child(tabs)
	for index in range(3):
		var button: Button = app._button(tabs,["요약","전적","계정 관리"][index],func(): select_tab(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("profile_tab",["summary","history","manage"][index])
		button.toggle_mode = true
		tab_buttons.append(button)
	body_scroll = ScrollContainer.new()
	body_scroll.name = "ProfileBodyScroll"
	body_scroll.set_meta("profile_scroll",true)
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(body_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	for index in range(3):
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",14)
		page.set_meta("profile_page",["summary","history","manage"][index])
		body.add_child(page)
		pages.append(page)
	_build_summary(pages[0])
	load_history(pages[1])
	_build_manage(pages[2])
	select_tab(2 if app.me.get("weakPw",false) else 0,false)
	if app.me.get("weakPw",false): open_form("pw")

func select_tab(index: int,animate: bool=true) -> void:
	current_tab = clampi(index,0,2)
	for i in range(pages.size()):
		pages[i].visible = i==current_tab
		tab_buttons[i].set_pressed_no_signal(i==current_tab)
		app.ui_components._style_button(tab_buttons[i],"primary" if i==current_tab else "secondary")
	body_scroll.scroll_vertical = 0
	if animate:
		var page: Control = pages[current_tab]
		page.modulate.a = .45
		page.create_tween().tween_property(page,"modulate:a",1.0,.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_summary(parent: Node) -> void:
	var summary := _card(parent)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation",12)
	summary.add_child(identity)
	var piece := TextureRect.new()
	piece.texture = load("res://pieces/Chess_%slt45.svg" % str(app.me.get("tier","N")).to_lower())
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	piece.custom_minimum_size = Vector2(48,48)
	identity.add_child(piece)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(info)
	display_name = app._label(info,str(app.me.get("name","회원")),22)
	display_name.set_meta("profile_name",true)
	_muted(info,"%d점 · %s" % [int(app.me.get("rating",1000)),app.NAMES.get(app.me.get("tier","N"),"나이트")],16)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",12)
	summary.add_child(stats)
	for item in [["승리","wins"],["패배","losses"],["무승부","draws"]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(column)
		var value: Label = app._label(column,str(int(app.me.get(item[1],0))),22)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption: Label = _muted(column,item[0])
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tiers := [[500,"P"],[1000,"N"],[1200,"R"],[1500,"B"],[1700,"Q"],[1900,"K"]]
	var current := 0
	for i in range(tiers.size()):
		if app.me.get("tier")==tiers[i][1]: current = i
	var tier := _card(parent,"티어 · 레이팅")
	var rating := int(app.me.get("rating",1000))
	app._label(tier,"최고 티어 · 킹" if current==5 else "다음 %s까지 %d점" % [app.NAMES[tiers[current+1][1]],maxi(0,int(tiers[current+1][0])-rating)],18)
	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 8
	progress.value = 100 if current==5 else clampf((float(rating)-tiers[current][0])/(tiers[current+1][0]-tiers[current][0])*100,0,100)
	var track := StyleBoxFlat.new()
	track.bg_color = app.ui_components._palette().border
	track.set_corner_radius_all(4)
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = app.ui_components._palette().accent
	progress.add_theme_stylebox_override("background",track)
	progress.add_theme_stylebox_override("fill",fill)
	tier.add_child(progress)
	_muted(tier,"현재 %s · %d점" % [app.NAMES[tiers[current][1]],rating])
	var range_box := GridContainer.new()
	range_box.columns = 2
	range_box.add_theme_constant_override("h_separation",8)
	range_box.add_theme_constant_override("v_separation",8)
	var range_toggle: Button = app._button(tier,"티어 기준 보기 ▾",func():
		range_box.visible = not range_box.visible
		tier.get_node("TierToggle").text = "티어 기준 접기 ▴" if range_box.visible else "티어 기준 보기 ▾","tertiary")
	range_toggle.name = "TierToggle"
	range_toggle.set_meta("profile_action","tiers")
	tier.add_child(range_box)
	for i in range(tiers.size()):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		range_box.add_child(cell)
		var label: Label = app._label(cell,app.NAMES[tiers[i][1]]+(" · 현재" if i==current else ""),14)
		if i==current: label.add_theme_color_override("font_color",Color("#956922") if app.prefs.get_value("settings","light",false) else Color("#e5bf79"))
		_muted(cell,"500–999점" if i==0 else ("1900점 이상" if i==5 else "%d–%d점" % [tiers[i][0],int(tiers[i+1][0])-1]),13)
	range_box.hide()
	var chart_box := _card(parent,"최근 레이팅 대국",true)
	_load_trend(chart_box)

func _load_trend(parent: Node) -> void:
	var loading: Label = app._label(parent,"레이팅 기록을 불러오는 중…",14)
	loading.add_theme_color_override("font_color",Color("#b8c3c6"))
	var session: String = app.session
	var data: Dictionary = await app.api.request("/me/history",{"session":session,"rating_only":true})
	if not is_instance_valid(parent) or session!=app.session: return
	if not data.get("ok"):
		loading.text = "레이팅 기록을 불러오지 못했습니다."
		var retry: Button = app._button(parent,"다시 불러오기",func(): loading.queue_free(); parent.get_node("TrendRetry").queue_free(); _load_trend(parent))
		retry.name = "TrendRetry"
		retry.set_meta("profile_action","trend_retry")
		return
	var rows: Array = data.get("rows",[])
	if rows.is_empty(): loading.text = "아직 레이팅 대국이 없습니다.\n첫 대국을 마치면 변화가 표시됩니다."; return
	loading.queue_free()
	var chart := ProfileTrend.new()
	chart.set_meta("profile_trend",true)
	parent.add_child(chart)
	chart.set_rows(rows)

func _build_manage(parent: Node) -> void:
	status = app._label(parent,"",14)
	status.set_meta("profile_status",true)
	status.hide()
	var warning_box := _card(parent)
	warning = warning_box.get_parent()
	app._label(warning_box,"비밀번호 업데이트가 필요합니다",16)
	_muted(warning_box,"현재 비밀번호는 이전 규칙입니다. 영문·숫자·특수문자를 포함한 8자 이상으로 바꿔 주세요.")
	warning.visible = bool(app.me.get("weakPw",false))
	manage_actions = VBoxContainer.new()
	manage_actions.add_theme_constant_override("separation",10)
	manage_actions.set_meta("profile_manage_actions",true)
	parent.add_child(manage_actions)
	app._label(manage_actions,"계정 정보와 보안",18)
	for item in [["name","닉네임 변경","게임에서 표시되는 이름"],["pw","비밀번호 변경","계정 비밀번호와 로그인 보안"],["recov","복구 코드 재발급" if app.me.get("hasRecovery",false) else "복구 코드 발급","비밀번호를 잊었을 때의 복구 수단"]]:
		var section: String = item[0]
		var button: Button = app._button(manage_actions,str(item[1]),func(): open_form(section))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 48
		button.set_meta("profile_action",section)
		_muted(manage_actions,item[2],13)
	var divider := HSeparator.new()
	manage_actions.add_child(divider)
	var logout: Button = app._button(manage_actions,"로그아웃",_logout)
	logout.custom_minimum_size.y = 48
	logout.set_meta("profile_action","logout")
	_muted(manage_actions,"이 기기에서 로그아웃합니다.",13)
	var deletion := _card(manage_actions,"계정 삭제")
	_muted(deletion,"계정·레이팅·개인 전적을 영구 삭제합니다.",14)
	var remove: Button = app._button(deletion,"계정 삭제 안내",func(): window.queue_free(); account._delete_form(),"danger")
	remove.set_meta("profile_action","delete")
	form_host = VBoxContainer.new()
	form_host.add_theme_constant_override("separation",10)
	form_host.set_meta("profile_forms",true)
	form_host.set_meta("management_actions",manage_actions)
	form_host.set_meta("profile_warning",warning)
	form_host.set_meta("profile_scroll",body_scroll)
	parent.add_child(form_host)
	form_host.hide()

func open_form(section: String) -> void:
	manage_actions.hide()
	form_host.show()
	account._profile_form(form_host,section,status,display_name)
	body_scroll.scroll_vertical = 0

func _logout() -> void:
	var button: Button
	for node in manage_actions.get_children():
		if node.get_meta("profile_action","")=="logout": button = node
	if is_instance_valid(button): button.disabled = true
	var data: Dictionary = await app.api.request("/logout",{"session":app.session})
	if data.get("ok"):
		app.session = ""
		app.me = {}
		app._save()
		app._update_account()
		if is_instance_valid(window): window.queue_free()
	elif is_instance_valid(status):
		status.text = str(data.get("msg","로그아웃하지 못했습니다. 다시 시도해 주세요."))
		status.show()
		if is_instance_valid(button): button.disabled = false

func load_history(parent: Node,with_trend: bool=false) -> void:
	if with_trend: _load_trend(_card(parent,"최근 레이팅 대국",true))
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation",12)
	host.set_meta("profile_history",true)
	parent.add_child(host)
	var title: Label = app._label(host,"최근 전적을 불러오는 중…",16)
	var session: String = app.session
	var data: Dictionary = await app.api.request("/me/history",{"session":session})
	if not is_instance_valid(host) or session!=app.session: return
	if not data.get("ok"):
		title.text = "전적을 불러오지 못했습니다"
		_muted(host,str(data.get("msg","연결을 확인하고 다시 시도해 주세요.")))
		var retry: Button = app._button(host,"다시 불러오기",func(): host.queue_free(); load_history(parent))
		retry.set_meta("profile_action","history_retry")
		return
	var rows: Array = data.get("rows",[])
	if rows.is_empty():
		title.text = "아직 대국 기록이 없습니다"
		_muted(host,"첫 대국을 마치면 최근 20판의 결과와 레이팅 변화를 여기서 확인할 수 있습니다.")
		host.set_meta("profile_history_state","empty")
		return
	host.set_meta("profile_history_state","loaded")
	host.set_meta("profile_history_count",rows.size())
	var wins := 0
	var losses := 0
	var draws := 0
	var total := 0
	var rated := 0
	for entry in rows:
		if entry.result=="win": wins += 1
		elif entry.result=="loss": losses += 1
		else: draws += 1
		if entry.get("rated",false): total += int(entry.get("delta",0)); rated += 1
	title.text = "최근 %d판" % rows.size()
	_muted(host,"%d승 · %d패 · %d무%s" % [wins,losses,draws," · 레이팅 %+d" % total if rated else ""])
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation",6)
	host.add_child(pager)
	var previous: Button = app._button(pager,"이전",func(): pass)
	previous.set_meta("profile_action","history_previous")
	var page_label: Label = app._label(pager,"",14)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.set_meta("profile_history_page",true)
	var next: Button = app._button(pager,"다음",func(): pass)
	next.set_meta("profile_action","history_next")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",10)
	host.add_child(list)
	var state := {"page":0}
	var render := func():
		for child in list.get_children(): list.remove_child(child); child.queue_free()
		var pages_count := ceili(rows.size()/5.0)
		page_label.text = "%d / %d" % [state.page+1,pages_count]
		previous.disabled = state.page==0
		next.disabled = state.page>=pages_count-1
		for index in range(state.page*5,mini((state.page+1)*5,rows.size())): _history_row(list,rows[index],index)
	previous.pressed.connect(func(): state.page-=1; render.call())
	next.pressed.connect(func(): state.page+=1; render.call())
	render.call()

func _history_row(parent: Node,entry: Dictionary,index: int) -> void:
	var row := _card(parent)
	row.set_meta("profile_history_row",index)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",10)
	row.add_child(heading)
	var outcome: Label = app._label(heading,{"win":"승리","loss":"패배","draw":"무승부"}.get(entry.get("result",""),"대국"),16)
	outcome.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	outcome.autowrap_mode = TextServer.AUTOWRAP_OFF
	outcome.custom_minimum_size.x = 48
	var name: Label = app._label(heading,str(entry.get("opp_name","상대")),15)
	name.set_meta("profile_opponent",true)
	var delta: Label = app._label(heading,"%+d" % int(entry.get("delta",0)) if entry.get("rated",false) else "—",15)
	delta.size_flags_horizontal = Control.SIZE_SHRINK_END
	delta.autowrap_mode = TextServer.AUTOWRAP_OFF
	delta.custom_minimum_size.x = 40
	delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if entry.get("rated",false): delta.add_theme_color_override("font_color",Color("#275f87") if app.prefs.get_value("settings","light",false) else Color("#9cc6e6"))
	var kind: String = {"match":"랭크","bot":"컴퓨터","lobby":"친구"}.get(entry.get("kind",""),"대국")
	_muted(row,kind+(" · 상대 %d점" % int(entry.opp_rating) if entry.get("opp_rating")!=null else "")+(" · 비레이팅" if not entry.get("rated",false) else ""),13)
	var reason: String = {"king":"왕 처치","resign":"기권","disconnect":"접속 끊김","timeout":"미행동","draw":"턴 한도"}.get(entry.get("reason",""),"")
	if entry.get("result")=="win" and entry.get("reason") in ["resign","disconnect","timeout"]: reason = "상대 "+reason
	var date := Time.get_datetime_dict_from_unix_time(int(entry.get("created",0))+int(Time.get_time_zone_from_system().bias)*60)
	_muted(row,"%s%s%02d-%02d %02d:%02d" % [reason," · " if not reason.is_empty() else "",date.month,date.day,date.hour,date.minute],13)
