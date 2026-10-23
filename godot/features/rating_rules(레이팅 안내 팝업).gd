extends RefCounted
## Presentation only: every rating number comes from the leaderboard rules payload.
var app: Control
func _init(context: Control) -> void: app = context

func _section(parent: Node, icon: String, title: String, subtitle: String="") -> VBoxContainer:
	var box: VBoxContainer = app._card(parent,"")
	box.add_theme_constant_override("separation",12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",10)
	box.add_child(head)
	app._icon(head,icon,32)
	app._label(head,title,17)
	if not subtitle.is_empty():
		var note: Label = app._label(box,subtitle,13)
		note.add_theme_color_override("font_color",app.ui_components._palette().muted)
	return box

func _metric(parent: Node, title: String, value: String, node_name: String) -> void:
	var box: VBoxContainer = app._card(parent,"")
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app._label(box,title,12)
	var number: Label = app._label(box,value,26)
	number.name = node_name
	number.add_theme_color_override("font_color",Color("9b6c2d") if app.prefs.get_value("settings","light",false) else Color("e7c68d"))

func _cell(grid: GridContainer, text: String, header: bool=false, delta: int=99999, node_name: String="") -> void:
	var colors: Dictionary = app.ui_components._palette()
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = colors.button if header else colors.surface
	style.border_color = colors.border
	style.border_width_bottom = 1
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",style)
	grid.add_child(panel)
	var label: Label = app._label(panel,text,12 if header else (18 if delta!=99999 else 13))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not node_name.is_empty(): label.name = node_name
	if delta!=99999 and delta!=0:
		var light: bool = app.prefs.get_value("settings","light",false)
		label.add_theme_color_override("font_color",(Color("286d49") if light else Color("a4d3b4")) if delta>0 else colors.danger)

func _restore(previous_ref: WeakRef, trigger_ref: WeakRef) -> void:
	var previous: Window = previous_ref.get_ref() if previous_ref!=null else null
	var trigger: Button = trigger_ref.get_ref() if trigger_ref!=null else null
	if not is_instance_valid(previous) or previous.is_queued_for_deletion(): return
	for child in app.get_children():
		if child is Window and child.visible and not child.is_queued_for_deletion(): return
	previous.show()
	if is_instance_valid(trigger): trigger.grab_focus()

func show_rules(rule: Dictionary, previous: Window=null, trigger: Button=null) -> Window:
	var pair: Array = app._small_window("레이팅 규칙",680,760)
	var window: Window = pair[0]
	window.name = "RatingRulesDialog"
	window.set_meta("suppress_hover_tooltips",true)
	var previous_ref: WeakRef = weakref(previous) if is_instance_valid(previous) else null
	var trigger_ref: WeakRef = weakref(trigger) if is_instance_valid(trigger) else null
	window.tree_exited.connect(func(): _restore(previous_ref,trigger_ref))
	var body: VBoxContainer = pair[1]
	# Keep the title/close and confirmation controls reachable while the body scrolls.
	var scroll: ScrollContainer = body.get_parent()
	scroll.name = "RatingRulesScroll"
	var panel: PanelContainer = scroll.get_parent()
	panel.remove_child(scroll)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	panel.add_child(layout)
	var head: HBoxContainer = body.get_child(0)
	body.remove_child(head)
	layout.add_child(head)
	layout.add_child(HSeparator.new())
	layout.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",12)
	body.add_child(stats)
	var base := int(rule.get("default",1000))
	var floor_rating := int(rule.get("floor",0))
	var k := int(rule.get("k",32))
	_metric(stats,"처음 시작할 때","%d점" % base,"StartingRating")
	_metric(stats,"최저 레이팅","%d점" % floor_rating,"RatingFloor")
	app._label(body,"티어는 현재 레이팅 구간에 따라 자동으로 바뀝니다.",13)
	var examples := _section(body,"trophy","상대 점수에 따른 변화","내 레이팅이 %d점일 때의 기본 변동 예시" % base)
	var table := GridContainer.new()
	table.name = "RatingExamples"
	table.columns = 4
	table.add_theme_constant_override("h_separation",0)
	table.add_theme_constant_override("v_separation",0)
	examples.add_child(table)
	for heading in ["상대","승리","패배","무승부"]: _cell(table,heading,true)
	for difference in [0,300,-300]:
		_cell(table,"%d점" % (base+difference))
		var expected := 1.0/(1.0+pow(10.0,float(difference)/400.0))
		for score in [1.0,0.0,.5]:
			var delta := int(floor(k*(score-expected)+.5))
			_cell(table,("+" if delta>0 else "")+str(delta),false,delta,"Delta_%s_%s" % [difference,int(score*2)])
	app._label(examples,"최저 점수와 컴퓨터 대국 상한을 적용하기 전의 예시입니다.",12)
	var calculation := VBoxContainer.new()
	examples.add_child(calculation)
	calculation.hide()
	var formula_button: Button = app._button(examples,"계산식 보기",func(): pass,"tertiary")
	examples.move_child(formula_button,calculation.get_index())
	formula_button.pressed.connect(func():
		calculation.visible = not calculation.visible
		formula_button.text = "계산식 접기" if calculation.visible else "계산식 보기")
	app._label(calculation,"변동 = %d × (결과 − 기대승률)" % k,14)
	app._label(calculation,"결과: 승리 1 · 무승부 0.5 · 패배 0\n기대승률 = 1 ÷ (1 + 10^((상대 점수 − 내 점수) ÷ 400))\n400점 차이는 승산 비율 10배에 해당합니다.",12)
	var ranked := _section(body,"rank","랭크 매칭","로그인 회원끼리의 대국에 적용됩니다.")
	app._label(ranked,"승리하면 상승 · 패배하면 하락\n무승부는 상대와의 점수 차이에 따라 달라집니다.",14)
	var bots := _section(body,"computer","컴퓨터와 대국")
	if rule.get("botRated",false):
		var benefit: Label = app._label(bots,"승리 시 상승 · 패배 시 하락 없음" if rule.get("botNoLoss",false) else "승리 시 상승 · 패배 시 하락",15)
		benefit.name = "BotRatingPolicy"
		var ratings: Dictionary = rule.get("bot",{})
		var levels := GridContainer.new()
		levels.columns = 3
		levels.add_theme_constant_override("h_separation",0)
		levels.add_theme_constant_override("v_separation",0)
		bots.add_child(levels)
		for text in ["난이도","상대 점수","상승 상한"]: _cell(levels,text,true)
		for level in ["easy","normal","hard"]:
			var value := int(ratings.get(level,0))
			_cell(levels,{"easy":"쉬움","normal":"보통","hard":"어려움"}[level])
			_cell(levels,str(value))
			_cell(levels,str(value+int(rule.botCap)) if rule.get("botCap")!=null else "제한 없음",false,99999,"BotCap_"+level)
		if rule.get("botCap")!=null: app._label(bots,"상한에 도달하면 랭크 매칭에서 더 높이 올라갈 수 있어요.",12)
	else: app._label(bots,"컴퓨터 대국은 레이팅에 반영되지 않습니다.",14)
	var other := _section(body,"lobby","점수가 바뀌지 않는 대국")
	app._label(other,"친구 대전 · 혼자 연습 · 게스트 플레이",14)
	var notice := _section(body,"book","대국이 끝나면 한 번 정산")
	app._label(notice,"기권, 접속 끊김 90초, 연속 3회 미행동은 패배로 처리됩니다.",13)
	layout.add_child(HSeparator.new())
	var done: Button = app._button(layout,"확인",window.close_requested.emit,"primary")
	done.name = "RatingRulesDone"
	app._layout()
	return window
