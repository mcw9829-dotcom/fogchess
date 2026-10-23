extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

func _init(context: Control) -> void:
	app = context

func _effect(data: Dictionary) -> void:
	if int(data.get("seq",0))<=app.last_fx: return
	app.last_fx = int(data.seq)
	var visual = data.duplicate(true)
	var cells: Array = data.get("cells",[])
	if not visual.has("from"): visual["from"] = app._fx_origin(str(data.get("type","move")),cells)
	visual["extra"] = []
	if data.get("type")=="scan":
		for rc in cells:
			var piece: Variant = app.board.tile(Vector2i(rc[0],rc[1])).get("p")
			if piece is Dictionary and piece.o!=app.view.get("yourColor"): visual.extra.append(rc)
	app.board.play_fx(visual)
	var cue = str(data.get("type","move"))
	if cue in ["capture","kill"] and not app.board.piece_motion.is_empty():
		app.board.fx.after(float(app.board.piece_motion.duration),func(): app.audio.cue(cue))
	else: app.audio.cue(cue)

func _render() -> void:
	app.chat.render()
	var series: Dictionary = app.view.get("series") if app.view.get("series") is Dictionary else {}
	var phase: String = app.view.get("phase","")
	var my_turn: bool = app.view.get("turn")==app.view.get("yourColor")
	var headline = "배치 단계" if phase=="setup" else ("내 차례" if my_turn else "상대 차례")
	if not app.view.get("bothJoined",false): headline = "친구 접속 대기 · 방 코드를 공유하세요"
	if app.seat=="spectator": headline = "방이 가득 찼습니다 · 관전자"
	if phase=="over": headline = "대국 종료"
	var seconds: Variant = app.view.get("secondsLeft") if phase=="setup" else app.view.get("turnSecondsLeft")
	app.state_label.text = headline
	if app.view.get("solo") and phase=="play": app.state_label.text = "지금 %s 차례" % ("백" if app.view.get("turn")=="W" else "흑")
	app.clock_label.text = "%02d:%02d" % [int(seconds)/60,int(seconds)%60] if seconds!=null and phase!="over" else "—"
	app.turn_meta.text = "%d / %d수" % [int(app.view.get("turnCount",0)),int(app.view.get("turnLimit",200))] if phase!="setup" else "배치 시간"
	app.series_label.visible = not series.is_empty() and phase!="over"
	app.ui_shell.state_group.custom_minimum_size.y = 42
	if not series.is_empty(): app.series_label.text = "%d : %d · %s" % [int(series.me),int(series.opp),"종료" if series.complete else ("최종전" if series.final else "먼저 2승")]
	app.warning_label.text = ""
	app.warning_label.hide()
	app.opponent_line.text = str(app.view.get("oppName","상대"))
	app.ui_shell.opponent_rating.text = app._rating(app.view.get("oppRating"))
	app.ui_shell.opponent_rating.visible = app.seat!="spectator" and app.view.get("oppRating")!=null
	app.self_line.text = "%s · 나   %s" % [str(app.view.get("myName","나")),app._rating(app.view.get("myRating"))]
	app.room_label.get_parent().get_parent().visible = phase=="setup"
	app.my_panel.get_parent().get_parent().hide()
	app.utility_actions.visible = phase!="play"
	app.utility_actions.get_node("LeaveMatch").text = app.game_session.leave_label()
	app.room_label.text = "%s · %s\n방 %s · 맵 #%s" % ["혼자 연습" if app.view.get("solo") else ("컴퓨터 대국" if app.view.get("bot") else "친구 / 랭크 대전"),"백" if app.view.get("yourColor")=="W" else "흑",app.room,int(app.view.get("mapSeed",0))]
	app.invite_row.visible = not app.view.get("bothJoined",false) and app.seat!="spectator"
	app.invite_field.text = app.api.base_url+"/godot/#"+app.room
	app.opponent_panel.update_player(app.view,false,bool(app.prefs.get_value("settings","light",false)))
	app.my_panel.update_player(app.view,true,bool(app.prefs.get_value("settings","light",false)))
	var elapsed = int(app.view.get("elapsed") if app.view.get("elapsed")!=null else 0)
	app.players_label.text = ("친구 접속 대기" if seconds==null else "배치 %d초" % int(seconds)) if phase=="setup" else "%02d:%02d                       %d/%d턴" % [int(elapsed/60),elapsed%60,int(app.view.get("turnCount",0)),int(app.view.get("turnLimit",200))]
	app.status_label.text = headline
	var misses: Dictionary = app.view.get("misses",{})
	if int(misses.get(app.view.get("yourColor"),0))>0: app.status_label.text += " · 내 미행동 %d/3" % int(misses.get(app.view.get("yourColor"),0))
	if phase=="play":
		var mine_misses = int(misses.get(app.view.get("yourColor"),0))
		var other_misses = int(misses.get("B" if app.view.get("yourColor")=="W" else "W",0))
		if mine_misses>0: app.warning_label.text = "미행동 %d/3 · 연속 3회면 패배합니다." % mine_misses
		if my_turn and seconds!=null and int(seconds)<=10: app.warning_label.text = "시간 부족 · 행동 선택" if app.size.x<480 else "시간이 얼마 남지 않았어요. 행동을 선택하세요."
		app.warning_label.visible = not app.warning_label.text.is_empty()
		if other_misses>0: app.opponent_line.text += " · 미행동 %d/3" % other_misses
		var exposed: Array = app.view.get("exposed",[])
		if not exposed.is_empty():
			app.self_line.text += " · ! 적 시야에 노출 %d개" % exposed.size()
	app.result_panel.visible = phase=="over"
	app.reveal_button.text = "안개 걷힘 ON" if app.reveal else "안개 걷힘 OFF"
	app.sound_button.text = "소리 켜짐" if app.audio.enabled else "소리 꺼짐"
	app._render_feed()
	app.setup_controls.visible = phase=="setup" and app.seat!="spectator"
	app.ready_button.visible = app.setup_controls.visible
	app.ready_button.text = "준비 취소" if app.view.get("ready") else "준비 완료"
	app.ready_button.disabled = app.busy
	app.reveal_button.visible = bool(app.view.get("solo",false))
	app.resign_button.visible = phase!="over" and app.seat!="spectator"
	app.over_controls.hide() # Result panel owns the next action; avoid duplicate invitations.
	app.result_label.visible = phase=="over"
	if phase=="over": app._render_result()
	else: app.result_signature = ""
	app.history_label.get_parent().get_node("HistoryPolicy").text = "리플레이: 이 수까지의 양쪽 행동" if app.replay.active else ("관전: 3분 전 양쪽 행동" if app.seat=="spectator" else "내 행동만 표시합니다.")
	app.match_ui.render_history()
	var mine: bool = phase=="play" and app.view.get("turn")==app.view.get("yourColor")
	var light: bool = app.prefs.get_value("settings","light",false)
	var tint = (Color("#76521e") if light else Color("#d4a34a")) if mine or phase=="over" else ((Color("#286599") if light else Color("#9ac8ff")) if phase=="setup" else app.ui_components._palette().muted)
	app.state_label.add_theme_color_override("font_color",tint)
	app.clock_label.add_theme_color_override("font_color",(Color("#a24720") if light else Color("#efad83")) if mine and seconds!=null and int(seconds)<=10 else tint)
	if phase=="over" or seconds==null: app.clock_label.add_theme_color_override("font_color",app.ui_components._palette().muted)
	app.match_ui.hourglass.visible = seconds!=null and phase in ["setup","play"]
	app.match_ui.hourglass.set_state(seconds!=null and float(seconds)>0 and phase in ["setup","play"] and not app.replay.active and not app.game_session.awaiting_state,app.clock_label.get_theme_color("font_color"))
	app.warning_label.add_theme_color_override("font_color",Color("#934c20") if light else Color("#edb578"))
	app.opponent_line.tooltip_text = app.opponent_line.text+" "+app.ui_shell.opponent_rating.text
	app.self_line.tooltip_text = app.self_line.text
	app._update_selection_ui()
	app.coach_label.get_parent().get_parent().visible = phase!="over" and not app.match_ui.mobile_actions_active()
	app.spectating.render()
	app.match_ui.render()
	app.ui_motion.observe_view()
	_refresh_menu()
	if phase=="play" and my_turn and app.view.get("promote") and not is_instance_valid(app.promote_window): app._promotion()
	elif (phase!="play" or not my_turn or not app.view.get("promote")) and is_instance_valid(app.promote_window): app.promote_window.queue_free()

func _rating(value: Variant) -> String:
	return "" if value==null else "%d점" % int(value)

func _piece_names(items: Array) -> String:
	var names: Array[String] = []
	for item in items: names.append(app.NAMES.get(item,item))
	return "·".join(names) if not names.is_empty() else "없음"

func _render_feed() -> void:
	var feed: Array = app.view.get("feed",[])
	var captured: Array = app.view.get("captured",[])
	var signature = str([app.game_ux.feed_expanded,feed,captured,app.view.get("capturedBy",{}),app.view.get("yourColor"),app.room,app.prefs.get_value("settings","light",false)])
	if signature==app.feed_signature: return
	var previous = app.feed_signature
	app.feed_signature = signature
	if app.enemy_icons.has_meta("watch_signature"): app.enemy_icons.remove_meta("watch_signature")
	app.enemy_counts.text = "내가 잡은 기물 · %d개" % captured.size()
	app.enemy_counts.visible = app.seat!="spectator" and not captured.is_empty()
	app.enemy_icons.visible = app.seat!="spectator" and not captured.is_empty()
	for child in app.enemy_icons.get_children():
		app.enemy_icons.remove_child(child)
		child.queue_free()
	var opponent = "B" if app.view.get("yourColor")=="W" else "W"
	var pawns = captured.count("P")
	if pawns>0:
		var group = HBoxContainer.new()
		group.tooltip_text = "잡은 폰 %d개" % pawns
		app.enemy_icons.add_child(group)
		var pawn = app._feed_icon(group,"P",opponent)
		pawn.custom_minimum_size = Vector2(20,20)
		pawn.get_parent().custom_minimum_size = Vector2(24,24)
		var count_label = app._label(group,"×%d" % pawns,13)
		count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		count_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for kind in ["N","B","R","Q","K"]:
		for index in range(captured.count(kind)):
			var icon = app._feed_icon(app.enemy_icons,kind,opponent)
			icon.custom_minimum_size = Vector2(36,36)
			icon.get_parent().custom_minimum_size = Vector2(40,40)
	for child in app.feed_box.get_children():
		app.feed_box.remove_child(child)
		child.queue_free()
	if feed.is_empty(): app._label(app.feed_box,"아직 교전 기록이 없습니다.",13)
	var light: bool = app.prefs.get_value("settings","light",false)
	var mine_color := Color("#76521e") if light else Color("#dfac50")
	var opponent_color := Color("#285d89") if light else Color("#8ab5e0")
	var reversed = feed.slice(0 if app.game_ux.feed_expanded else maxi(0,feed.size()-3)).duplicate()
	reversed.reverse()
	for entry in reversed:
		var mine = entry.get("actor")==("W" if app.seat=="spectator" else app.view.get("yourColor"))
		var friendly = entry.get("actor")==entry.get("victim")
		var method = {"melee":"포획","artillery":"저격","barrage":"돌파"}.get(entry.get("method"),"공격")
		var strip = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = app.ui_components._palette().button
		style.border_color = mine_color if mine else opponent_color
		style.border_width_left = 2
		style.set_corner_radius_all(4)
		style.content_margin_left = 5
		style.content_margin_right = 5
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		strip.add_theme_stylebox_override("panel",style)
		strip.tooltip_text = "%s %s → %s %s · %s%s" % ["내" if mine else "상대",app.NAMES.get(entry.get("atype"),""),"내" if entry.get("victim")==app.view.get("yourColor") else "상대",app.NAMES.get(entry.get("vtype"),""),method," · 아군 피해" if friendly else ""]
		if app.seat=="spectator":
			strip.tooltip_text = "%s %s → %s %s · %s" % ["백" if entry.get("actor")=="W" else "흑",app.NAMES.get(entry.get("atype"),""),"백" if entry.get("victim")=="W" else "흑",app.NAMES.get(entry.get("vtype"),""),method]
		app.feed_box.add_child(strip)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation",4)
		strip.add_child(row)
		var owner = app._label(row,("백" if entry.get("actor")=="W" else "흑") if app.seat=="spectator" else ("나" if mine else "적"),13)
		owner.add_theme_color_override("font_color",mine_color if mine else opponent_color)
		owner.autowrap_mode = TextServer.AUTOWRAP_OFF
		owner.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		app._feed_icon(row,str(entry.get("atype","P")),str(entry.get("actor","W")))
		var weapon_box = VBoxContainer.new()
		weapon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapon_box.add_theme_constant_override("separation",0)
		row.add_child(weapon_box)
		var weapon = preload("res://kill_method_icon(킬로그 공격 방식).gd").new()
		weapon.method = str(entry.get("method","melee"))
		weapon.ink = Color("#514938") if light else Color("#eee2cc")
		weapon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		weapon_box.add_child(weapon)
		var action = app._label(weapon_box,method,12)
		action.add_theme_color_override("font_color",app.ui_components._palette().muted)
		action.autowrap_mode = TextServer.AUTOWRAP_OFF
		action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app._feed_icon(row,str(entry.get("vtype","P")),str(entry.get("victim","B")))
		if friendly: app._label(row,"아군",10).add_theme_color_override("font_color",app.ui_components._palette().muted)
		if entry==reversed[0] and not previous.is_empty() and app.board.effects:
			strip.modulate.a = .35
			app.create_tween().tween_property(strip,"modulate:a",1.0,.18)

func _feed_icon(parent: Node, kind: String, color: String) -> TextureRect:
	var icon = TextureRect.new()
	var safe_kind = kind if kind in ["K","Q","R","B","N","P"] else "P"
	icon.texture = load("res://pieces/Chess_%s%st45.svg" % [safe_kind.to_lower(),"l" if color=="W" else "d"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28,28)
	icon.tooltip_text = ("백 " if color=="W" else "흑 ")+app.NAMES[safe_kind]
	var backdrop = PanelContainer.new()
	backdrop.custom_minimum_size = Vector2(30,30)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#bca789")
	style.set_corner_radius_all(5)
	backdrop.add_theme_stylebox_override("panel",style)
	parent.add_child(backdrop)
	backdrop.add_child(icon)
	return icon

func _fx_origin(_kind: String,_cells: Array) -> Variant:
	# Only locally confirmed actions carry a source. Server views intentionally omit enemy origins.
	return null

func _render_result() -> void:
	app.replay.remember()
	var solo: bool = app.view.get("solo",false) or app.seat=="solo"
	var won: bool = app.view.get("winner")==app.view.get("yourColor")
	app.result_label.text = "무승부" if app.view.get("winner")=="draw" else (("백" if app.view.winner=="W" else "흑")+" 승리" if solo else ("승리!" if won else "패배"))
	var reason = "적 왕 처치" if won else "내 왕이 당했다"
	var logs: Array = app.view.get("log",[])
	var tail = " ".join(logs.slice(maxi(0,logs.size()-3)))
	if "접속 끊김" in tail: reason = "상대 접속 끊김 · 기권 처리" if won else "접속 끊김 · 기권 처리"
	elif "미행동" in tail: reason = "상대 미행동 3회" if won else "미행동 3회"
	elif "기권" in tail: reason = "상대 기권" if won else "기권"
	if solo: reason = "혼자 연습"
	if app.view.get("winner")=="draw": reason = "턴 한도 도달"
	var delta: Variant = app.view.get("ratingDelta")
	if delta is Dictionary:
		reason += " · 레이팅 변동 없음(%d)" % int(delta.get("rating",0)) if int(delta.get("delta",0))==0 else " · 레이팅 %+d → %d" % [int(delta.delta),int(delta.get("rating",0))]
	var series: Dictionary = app.view.get("series") if app.view.get("series") is Dictionary else {}
	app.result_score.visible = not series.is_empty()
	if not series.is_empty():
		app.result_score.text = "나  %d  :  %d  상대" % [int(series.me),int(series.opp)]
		if not solo:
			app.result_label.text = ("시리즈 승리" if series.get("winner")==app.view.get("yourColor") else "시리즈 패배") if series.get("complete",false) else ("이번 판 무승부" if app.view.get("winner")=="draw" else ("이번 판 승리" if won else "이번 판 패배"))
		if not series.get("complete",false): reason += " · 먼저 2승하면 종료"
		if series.complete: reason += " · 시리즈 승리" if series.winner==app.view.get("yourColor") else " · 시리즈 패배"
		elif series.final: reason += " · 다음은 최종전"
		elif app.view.get("winner")=="draw": reason += " · 무승부는 승수 제외"
	if app.view.get("settlementPending",false): reason += "\n결과 저장 중 · 자동으로 다시 시도합니다."
	app.result_sub.text = reason
	var rematch: Dictionary = app.view.get("rematch",{})
	var signature = str([series,solo,app.view.get("bot"),app.view.get("oppConnected"),rematch,app.view.get("rated"),app.seat,app.view.get("replayId")])
	if signature==app.result_signature: return
	app.result_signature = signature
	app._clear_form(app.result_actions)
	if app.seat=="spectator":
		app._button(app.result_actions,"관전 마치기",app._leave_prompt)
	elif solo or app.view.get("bot",false):
		app._button(app.result_actions,"다시 대국",func(): await app._act({"type":"rematch"}),"primary")
	elif series.get("complete",false):
		app._label(app.result_actions,"2선승 시리즈 종료 · 재대결 불가",14)
		app._button(app.result_actions,"새 랭크 매칭",func(): app._return_home(); await app._match_command("join"),"primary")
		app._button(app.result_actions,"홈으로",app._return_home)
	elif not app.view.get("oppConnected",false):
		app._label(app.result_actions,"상대가 나갔어요",14)
		app._button(app.result_actions,"홈으로",app._leave_prompt)
	elif rematch.get("me",false) and not rematch.get("opp",false):
		app._label(app.result_actions,"다음 판을 제안했어요 · 상대 응답 대기 중…",14)
		app._button(app.result_actions,"제안 취소",func(): await app._act({"type":"rematch_decline"}))
		app._button(app.result_actions,"홈으로",app._leave_prompt)
	elif rematch.get("opp",false) and not rematch.get("me",false):
		app._label(app.result_actions,"상대가 다음 판을 제안했어요"+(" · 수락하면 같은 상대와 새 레이팅전(배치부터)" if app.view.get("rated",false) else ""),14)
		app._button(app.result_actions,"다음 판 수락",func(): await app._act({"type":"rematch"}),"primary")
		app._button(app.result_actions,"거절",func(): await app._act({"type":"rematch_decline"}))
	else:
		if app.view.get("rated",false): app._label(app.result_actions,"다음 판도 새 레이팅전 · 배치부터 시작",12)
		app._button(app.result_actions,"다음 판 제안",func(): await app._act({"type":"rematch"}),"primary")
		app._button(app.result_actions,"홈으로",app._leave_prompt)
		app._label(app.result_actions,"나가도 이번 판 결과는 그대로예요"+(" · 추가 레이팅 변동 없음" if app.view.get("rated",false) else ""),12)
	if app.view.get("replayId") and not app.replay.active:
		app._button(app.result_actions,"기보 / 리플레이 보기",func(): await app.replay.open(str(app.view.replayId),app.token),"tertiary")
	for child in app.result_actions.get_children():
		if child is Label: child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif child is Button:
			child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			child.custom_minimum_size.x = 200

func _game_menu() -> void:
	var pair = app._small_window("대국 메뉴",480,560)
	pair[0].name = "MatchMenu"
	var box: VBoxContainer = pair[1]
	box.add_theme_constant_override("separation",12)
	var info: VBoxContainer = app._card(box,"")
	app._label(info,app.match_ui.mode_label.text+" · "+("관전 중" if app.seat=="spectator" else ("백" if app.view.get("yourColor")=="W" else "흑")),14)
	var room_info: Label = app._label(info,"방 %s   ·   맵 #%s" % [app.room,int(app.view.get("mapSeed",0))],12)
	room_info.add_theme_color_override("font_color",app.ui_components._palette().muted)
	var clock_row := HBoxContainer.new()
	clock_row.name = "MenuClockRow"
	clock_row.add_theme_constant_override("separation",12)
	info.add_child(clock_row)
	var clock_state: Label = app._label(clock_row,"",14)
	clock_state.name = "MenuClockState"
	clock_state.autowrap_mode = TextServer.AUTOWRAP_OFF
	clock_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clock_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var menu_clock: Label = app._label(clock_row,"",28)
	menu_clock.name = "MenuClock"
	menu_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	menu_clock.size_flags_horizontal = Control.SIZE_SHRINK_END
	var resume := _menu_button(box,"보드로 돌아가기",pair[0].queue_free,"primary")
	resume.name = "ResumeMatch"
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation",10)
	actions.add_theme_constant_override("v_separation",10)
	box.add_child(actions)
	_menu_button(actions,"규칙 · 기물 설명",func(): pair[0].queue_free(); app._help())
	_menu_button(actions,"보드 표시 안내",func(): pair[0].queue_free(); app._board_help())
	_menu_button(actions,"설정",func(): pair[0].queue_free(); app._settings())
	var sound := _menu_button(actions,"효과음: "+("켜짐" if app.audio.enabled else "꺼짐"),func(): pass)
	sound.name = "MatchSound"
	sound.pressed.connect(func():
		app._toggle_sound()
		sound.text = "효과음: "+("켜짐" if app.audio.enabled else "꺼짐"))
	box.add_child(HSeparator.new())
	var note: Label = app._label(box,"메뉴를 열어도 대국 시간은 흐릅니다." if app.view.get("phase") in ["setup","play"] and app.seat!="spectator" and not app.replay.active else "기보와 결과는 대국 화면에서 확인할 수 있어요.",12)
	note.add_theme_color_override("font_color",app.ui_components._palette().muted)
	var exit_actions := HBoxContainer.new()
	exit_actions.add_theme_constant_override("separation",10)
	box.add_child(exit_actions)
	if app.view.get("phase") in ["setup","play"] and app.seat!="spectator" and not app.replay.active:
		var resign := _menu_button(exit_actions,"기권",func(): app.game_session.resign_prompt(),"danger")
		resign.name = "ResignMatch"
	var leave := _menu_button(exit_actions,app.game_session.leave_label(),func(): app._leave_prompt(),"danger" if app.game_session.leave_is_resignation() else "secondary")
	var exit_note: Label = app._label(box,"",12)
	exit_note.name = "ExitConsequences"
	leave.name = "LeaveMatch"
	_refresh_menu()
	resume.grab_focus()

func _refresh_menu() -> void:
	var menu: Window = app.get_node_or_null("MatchMenu")
	if not is_instance_valid(menu) or menu.is_queued_for_deletion(): return
	var clock: Label = menu.find_child("MenuClock",true,false)
	if not is_instance_valid(clock): return
	clock.get_parent().visible = app.view.get("phase") in ["setup","play"] and not app.replay.active
	clock.text = app.clock_label.text
	clock.add_theme_color_override("font_color",app.clock_label.get_theme_color("font_color"))
	menu.find_child("MenuClockState",true,false).text = "관전 · 지연된 시간" if app.seat=="spectator" else app.state_label.text
	var leave: Button = menu.find_child("LeaveMatch",true,false)
	if is_instance_valid(leave):
		leave.text = app.game_session.leave_label()
		leave.accessibility_name = leave.text
		app.ui_components._style_button(leave,"danger" if app.game_session.leave_is_resignation() else "secondary")
		leave.tooltip_text = "확인 후 기권 패배로 처리하고 홈으로 돌아갑니다." if app.game_session.leave_is_resignation() else "홈으로 돌아갑니다."
	menu.find_child("ExitConsequences",true,false).text = "둘 다 기권 패배입니다.\n기권: 결과 화면 · 기권 후 나가기: 홈으로" if app.game_session.leave_is_resignation() else ""
	var resign: Button = menu.find_child("ResignMatch",true,false)
	if is_instance_valid(resign): resign.visible = app.view.get("phase") in ["setup","play"] and app.seat!="spectator" and not app.replay.active

func _menu_button(parent: Node, text: String, callback: Callable, role: String="secondary") -> Button:
	var button: Button = app._button(parent,text,callback,role)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size",13)
	button.accessibility_name = text
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style: StyleBoxFlat = app.ui_components._button_style(role,state)
		style.content_margin_left = 10
		style.content_margin_right = 10
		if role!="danger" and state in ["hover","pressed"]:
			style.bg_color = Color("#f0d9b5") if state=="hover" else Color("#b58863")
			style.border_color = style.bg_color
		button.add_theme_stylebox_override(state,style)
	if role!="danger":
		button.add_theme_color_override("font_hover_color",Color("#241e14"))
		button.add_theme_color_override("font_pressed_color",Color("#241e14"))
	return button

func _board_help() -> void:
	var pair = app._window("보드 표시 도움말")
	app._label(pair[1],"● 이동할 수 있는 칸\n◎ 공격 가능한 대상\n색칠된 사각형: 능력 적용 범위\n어두운 칸: 시야 밖 — 적의 유무를 알 수 없음\n부쉬: 은폐 지형\n\n기물 클릭 → 행동 아이콘 → 목표 선택\n같은 기물 재선택 / 선택 안내의 × / 우클릭 / Esc: 선택 취소\n? 도움말: 호버 없이 행동 설명과 행동 변경 버튼 확인\n키보드: Tab 이동 · Enter 선택 · Esc 취소\n드래그 이동도 사용할 수 있습니다.\n이동 중 숨은 적을 만나면 그 칸에서 포획하고 멈춥니다.\n내 기물의 ! 표시: 상대에게 위치가 보이는 중입니다.\n모든 기물에 적용되며, 다시 은폐되면 사라집니다.\n부쉬 안에서도 연결된 부쉬의 적·스캔·사격 노출로 보일 수 있습니다.\n내 기물의 파란 ? 표시: 사격 후 내 차례 한 턴 동안 재장전 중입니다. 재장전은 이동·포획을 제한하지 않습니다. 실제 가능한 칸은 보드 표시로 확인하세요.\n승격 선택 시간이 끝나면 전차로 자동 승격합니다.",14)

func _compact_history(line: String) -> String:
	for event in ["resign","timeout","disconnect"]:
		if line.ends_with(" "+event) or line==event:
			return line.trim_suffix(event)+{"resign":"기권","timeout":"시간 초과","disconnect":"접속 종료"}[event]
	# Old replays keep their original data; shorten only the display, never infer captures.
	var words := line.split(" ",false)
	var names := {"킹":"K","퀸":"Q","전차":"R","룩":"R","비숍":"B","나이트":"N","폰":""}
	for i in range(words.size()):
		if not names.has(words[i]) or i+4>=words.size(): continue
		if words[i+3]!="→": continue
		var suffix: String = {"이동":"","저격":"!","돌파":">>","스캔":"?"}.get(words[i+2],"INVALID")
		if suffix=="INVALID": continue
		var prefix := " ".join(words.slice(0,i))
		return prefix+" "+str(names[words[i]])+suffix+words[i+4]
	return line
