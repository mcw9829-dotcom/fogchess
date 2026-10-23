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
		if int(app.prefs.get_value("settings","tutorial_step",0))>=3: await app._join({"vs_bot":true,"level":"easy"})
		else: app._tutorial(),"primary")
	learn_button.name = "LearningEntry"
	refresh_learning()
	practice_card = app.match_ui.card(app.controls,"연습 · 상황별 안내")
	app.controls.move_child(practice_card.get_parent(),3)
	practice_label = app._label(practice_card,"",13)
	practice_label.custom_minimum_size.y = 72
	var practice_actions := HFlowContainer.new()
	practice_card.add_child(practice_actions)
	practice_next = app._button(practice_actions,"알겠어요",func():
		seen_tips[active_tip] = true
		active_tip = ""
		render_practice(),"tertiary")
	app._button(practice_actions,"안내 끄기",func():
		app.prefs.set_value("settings","practice_tips",false)
		app._save()
		render_practice(),"tertiary")
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
	last_announcement = ""

func refresh_learning() -> void:
	if not is_instance_valid(learn_button): return
	var completed: bool = int(app.prefs.get_value("settings","tutorial_step",0))>=3
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
	var tips := {"fog":"어두운 칸은 빈칸이 아닙니다. 이동 중 숨은 적을 만나면 그 칸에서 포획하고 멈춥니다.","reload":"파란 ?는 재장전 상태입니다. 재장전은 이동·포획을 제한하지 않습니다. 현재 가능한 칸은 보드 표시로 확인하세요.","exposure":"노란 !는 내 위치가 상대에게 보인다는 뜻입니다. 누가 보고 있는지는 알려주지 않으며 다시 은폐되면 사라집니다."}
	practice_label.text = tips.get(active_tip,"새로운 노출·재장전 상황이 생기면 여기서 설명합니다. 규칙은 ? 도움말에서 다시 볼 수 있어요.")
	practice_next.disabled = active_tip.is_empty()

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
