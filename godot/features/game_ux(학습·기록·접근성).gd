extends RefCounted
## Presentation only: consumes the public server view and never infers hidden opponents.
var app
var scroll_bar: PanelContainer
var scroll_label: Label
var return_button: Button
var learn_button: Button
var learn_note: Label
var practice_card: VBoxContainer
var practice_label: Label
var practice_next: Button
var practice_off: Button
var practice_title: Label
var practice_icon: TextureRect
var practice_support: Label
var practice_disclosure: Button
var practice_extra: Label
var practice_divider: HSeparator
var practice_expanded := false
var displayed_tip := ""
var active_tip := ""
var seen_tips: Dictionary = {}
var feed_expanded := false
var feed_toggle: Button
var announcement: Label
var last_announcement := ""

func _init(context: Control) -> void:
	app = context

func action_name(mode: String) -> String:
	return {"choose":"행동 선택","move":"이동","attack":"공격","fire":"저격","barrage":"돌파","scan":"스캔"}.get(mode,"행동 선택")

func ability_mode() -> String:
	return {"B":"fire","R":"barrage","Q":"scan"}.get(app.selection.get("t",""),"none")

func ability_name() -> String:
	return action_name(ability_mode()) if ability_mode()!="none" else "고유 능력 없음"

func action_available(action: String) -> bool:
	if app.view.get("phase")!="play": return false
	if action in ["move","attack"]: return not app._move_targets(action=="attack").is_empty()
	if action in ["fire","barrage"] and app.moves.get("reloading",false): return false
	return bool(app.moves.get({"fire":"canFire","barrage":"canBarrage","scan":"canScan"}.get(action,""),false))

func build(page_root: VBoxContainer) -> void:
	scroll_bar = PanelContainer.new()
	scroll_bar.name = "RecordReturnBar"
	page_root.add_child(scroll_bar)
	page_root.move_child(scroll_bar,0)
	var row := HBoxContainer.new()
	scroll_bar.add_child(row)
	scroll_label = app._label(row,"",14)
	scroll_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return_button = app._button(row,"보드로",func():
		app.page_scroll.scroll_vertical = 0
		update_scroll_bar()
		app.match_ui.mobile_help.grab_focus(),"primary")
	return_button.accessibility_name = "시간과 체스판으로 돌아가기"
	scroll_bar.hide()
	app.page_scroll.get_v_scroll_bar().value_changed.connect(func(_value): update_scroll_bar())
	app.game.visibility_changed.connect(update_scroll_bar)
	var learn: VBoxContainer = app._card(app.menu,"")
	app.menu.move_child(learn.get_parent(),2)
	learn_note = app._label(learn,"처음이라면 · 시간제한 없이 직접 배우기",12)
	learn_button = app._button(learn,"",func():
		if int(app.prefs.get_value("settings","tutorial_step_v2",0))>=4: await app._join({"vs_bot":true,"level":"easy"})
		else: app._tutorial(),"primary")
	learn_button.name = "LearningEntry"
	refresh_learning()
	practice_card = app.match_ui.card(app.controls)
	app.controls.move_child(practice_card.get_parent(),3)
	var tip_header := HBoxContainer.new()
	tip_header.add_theme_constant_override("separation",8)
	practice_card.add_child(tip_header)
	practice_icon = TextureRect.new()
	practice_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	practice_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	practice_icon.custom_minimum_size = Vector2(24,28)
	tip_header.add_child(practice_icon)
	practice_title = app._label(tip_header,"",13)
	practice_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	practice_label = app._label(practice_card,"",18)
	practice_label.add_theme_constant_override("line_spacing",5)
	practice_support = app._label(practice_card,"",14)
	practice_support.add_theme_constant_override("line_spacing",4)
	practice_support.set_meta("match_muted",true)
	practice_divider = HSeparator.new()
	practice_card.add_child(practice_divider)
	practice_disclosure = app._button(practice_card,"",func():
		practice_expanded = not practice_expanded
		render_practice(),"tertiary")
	practice_disclosure.alignment = HORIZONTAL_ALIGNMENT_LEFT
	practice_disclosure.add_theme_font_size_override("font_size",13)
	practice_disclosure.custom_minimum_size.y = 48
	practice_extra = app._label(practice_card,"",14)
	practice_extra.add_theme_constant_override("line_spacing",5)
	var practice_actions := HBoxContainer.new()
	practice_actions.add_theme_constant_override("separation",8)
	practice_card.add_child(practice_actions)
	practice_next = app._button(practice_actions,"알겠어요",func():
		seen_tips[active_tip] = true
		active_tip = ""
		render_practice(),"primary")
	practice_off = app._button(practice_actions,"안내 끄기",func():
		app.prefs.set_value("settings","practice_tips",false)
		app._save()
		render_practice())
	for button in [practice_next,practice_off]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_card.get_parent().hide()
	var feed_card: VBoxContainer = app.feed_box.get_parent()
	feed_card.get_child(0).text = "대국 기록 · 킬로그"
	feed_toggle = app._button(feed_card,"",func():
		feed_expanded = not feed_expanded
		app.game_display._render_feed()
		render(),"tertiary")
	feed_card.move_child(feed_toggle,1)
	feed_toggle.add_theme_font_size_override("font_size",12)
	feed_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	announcement = app._label(page_root,"",1)
	# Live announcements change only at semantic transitions, never every second.
	announcement.custom_minimum_size = Vector2.ZERO
	announcement.clip_text = true
	announcement.modulate.a = 0
	announcement.accessibility_live = AccessibilityServer.LIVE_POLITE
	app.notice.accessibility_live = AccessibilityServer.LIVE_POLITE

func reset_room() -> void:
	feed_expanded = false
	seen_tips.clear()
	active_tip = ""
	displayed_tip = ""
	practice_expanded = false
	last_announcement = ""

func refresh_learning() -> void:
	if not is_instance_valid(learn_button): return
	var completed: bool = int(app.prefs.get_value("settings","tutorial_step_v2",0))>=4
	learn_button.text = "쉬움 봇으로 연습 계속하기" if completed else "직접 배우기 · 왕 찾기 미션"
	learn_button.accessibility_name = learn_button.text
	learn_note.text = "미션 완료 · 첫 대국으로 이어가기" if completed else "처음이라면 · 시간제한 없이 직접 배우기"

func update_scroll_bar() -> void:
	if not is_instance_valid(scroll_bar): return
	if not app.game.visible and is_instance_valid(announcement):
		announcement.text = ""
		last_announcement = ""
	var eligible: bool = app.game.visible and app.split.vertical and app.view.get("phase") in ["setup","play"] and not app.replay.active and app.seat!="spectator"
	var header_bottom: float = app.match_ui.turn_panel.get_global_rect().end.y-app.page_scroll.get_child(0).global_position.y
	var past_header: bool = app.page_scroll.scroll_vertical>0 and app.page_scroll.scroll_vertical>=header_bottom
	scroll_bar.visible = eligible and past_header
	if not scroll_bar.visible: return
	var low: bool = app.view.get("turn")==app.view.get("yourColor") and app.view.get("phase")=="play" and app.view.get("turnSecondsLeft")!=null and int(app.view.turnSecondsLeft)<=10
	scroll_label.text = ("시간 부족" if low else app.state_label.text)+" · "+app.clock_label.text
	scroll_label.add_theme_color_override("font_color",app.clock_label.get_theme_color("font_color"))
	scroll_bar.add_theme_stylebox_override("panel",app.match_ui._surface(app.ui_components._palette().surface,6,8))

func render_practice() -> void:
	if not is_instance_valid(practice_card): return
	var visible: bool = app.view.get("phase")=="play" and (app.view.get("bot",false) or app.view.get("solo",false)) and app.seat!="spectator" and not app.replay.active and bool(app.prefs.get_value("settings","practice_tips",true))
	practice_card.get_parent().visible = visible
	if not visible: return
	var eligible: Array[String] = []
	if not app.view.get("reloading",[]).is_empty(): eligible.append("reload")
	if not app.view.get("exposed",[]).is_empty(): eligible.append("exposure")
	eligible.append("fog")
	if active_tip.is_empty():
		for tip in eligible:
			if not seen_tips.has(tip): active_tip = tip; break
	if displayed_tip!=active_tip:
		displayed_tip = active_tip
		practice_expanded = false
	var tips := {
		"fog":["안개 속 이동","숨은 적을 만나면\n포획하고 멈춥니다","어두운 칸에도 적이 있을 수 있어요.","폰 이동 예외","정면 포획은 1칸만\n폰은 바로 앞의 적만 정면으로 포획할 수 있어요.\n\n첫 두 칸 전진은 다르게\n두 번째 칸에 숨은 적이 있으면 그 앞에서 멈춥니다."],
		"reload":["재장전","재장전은 이동·포획을\n막지 않아요","파란 ? 표시는 재장전 상태입니다.","가능한 행동 확인","보드 표시를 확인하세요\n현재 이동·포획할 수 있는 칸은 보드에 표시됩니다."],
		"exposure":["위치 노출","내 위치가\n상대에게 보입니다","노란 ! 표시가 있는 기물의 상태입니다.","어디까지 알려주나요?","관찰자는 알려주지 않아요\n어느 적 기물이 보고 있는지는 표시하지 않습니다.\n\n다시 은폐되면 사라져요\n노출이 끝나면 노란 ! 표시도 사라집니다."]}
	var tip: Array = tips.get(active_tip,["연습 · 상황별 안내","새 상황이 생기면\n다시 알려드릴게요","규칙은 ? 도움말에서 다시 볼 수 있어요.","",""])
	practice_title.text = tip[0]
	practice_label.text = tip[1]
	practice_support.text = tip[2]
	practice_disclosure.text = tip[3]+("  ▴" if practice_expanded else "  ▾")
	practice_disclosure.accessibility_name = tip[3]+(" 접기" if practice_expanded else " 펼치기")
	practice_extra.text = tip[4]
	practice_disclosure.visible = not active_tip.is_empty()
	practice_divider.visible = practice_disclosure.visible
	practice_extra.visible = practice_expanded and practice_disclosure.visible
	practice_next.disabled = active_tip.is_empty()
	practice_icon.texture = load("res://ui/icons/guide-%s.svg" % (active_tip if not active_tip.is_empty() else "fog"))
	var light: bool = app.prefs.get_value("settings","light",false)
	var blue := Color("#275f87") if light else Color("#a3ccef")
	practice_icon.modulate = (Color("#78521b") if light else Color("#e3bd78")) if active_tip=="exposure" else blue
	practice_title.add_theme_color_override("font_color",blue)
	practice_support.add_theme_color_override("font_color",app.ui_components._palette().muted)
	practice_extra.add_theme_color_override("font_color",app.ui_components._palette().text)
	for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]: practice_disclosure.add_theme_color_override(key,blue)

func render() -> void:
	if not is_instance_valid(feed_toggle): return
	update_scroll_bar()
	render_practice()
	var count: int = app.view.get("feed",[]).size()
	feed_toggle.visible = count>3
	feed_toggle.text = "받은 교전 기록 %d건 · 접기" % count if feed_expanded else "최근 3건 · 받은 기록 %d건 펼치기" % count
	feed_toggle.accessibility_name = feed_toggle.text
	var status: String = app.state_label.text
	if app.warning_label.visible: status += " · "+app.warning_label.text
	if app.seat!="spectator" and not app.replay.active:
		status += " · 내 노출 기물 %d" % app.view.get("exposed",[]).size()
	if status!=last_announcement:
		last_announcement = status
		announcement.text = status
