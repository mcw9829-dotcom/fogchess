extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

func _init(context: Control) -> void:
	app = context

func _help() -> void:
	var pair = app._small_window("기물 설명",1080,740)
	pair[0].set_meta("suppress_hover_tooltips",true)
	pair[0].name = "PieceGuide"
	var box: VBoxContainer = pair[1]
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",12)
	# Keep the title and piece/stage controls outside the scrollable explanation.
	var outer_scroll: ScrollContainer = box.get_parent()
	outer_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var header: HBoxContainer = box.get_child(0)
	var title: Label = header.get_child(0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var balance := Control.new()
	balance.custom_minimum_size.x = header.get_child(1).get_combined_minimum_size().x
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(balance)
	header.move_child(balance,0)
	var guide = preload("res://focused_guide(기물 설명 상세 화면).gd").new(app,pair[0])
	box.add_child(guide)

func _tutorial() -> void:
	if app.busy: return
	for child in app.get_children():
		if child is Window and child.visible: child.hide()
	var window = preload("res://features/ui_components(공통 버튼·입력·팝업).gd").DismissibleWindow.new()
	window.title = "직접 배우기 · 왕 찾기 미션"
	# Use the same viewport resize contract as other dialogs, retaining room
	# above the native-style title bar in short landscape windows.
	window.set_meta("preferred_size",Vector2i(1060,720))
	window.set_meta("viewport_margins",Vector2i(24,64))
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	app.add_child(window)
	var tutorial = preload("res://tutorial(튜토리얼 진행).gd").new()
	var saved = int(app.prefs.get_value("settings","tutorial_step_v2",0))
	tutorial.step = 0 if saved>=4 else saved
	tutorial.progress_changed.connect(func(value): app.prefs.set_value("settings","tutorial_step_v2",value); app._save(); app.game_ux.refresh_learning())
	tutorial.start_game.connect(func(): window.queue_free(); await app._join({"vs_bot":true,"level":"easy"}))
	window.add_child(tutorial)
	window.popup_centered(Vector2i(mini(int(app.get_viewport_rect().size.x)-24,1060),mini(int(app.get_viewport_rect().size.y)-64,720)))

func _intro(step: int=0) -> void:
	app.prefs.set_value("settings","intro_seen",true)
	app._save()
	var pair = app._small_window("안개전장 체스 · 1분 안내",560,524)
	var spec: Dictionary = preload("res://original_demo(원본 시연 재현).gd").scenes().intro[step]
	pair[1].add_theme_constant_override("separation",8)
	var head: HBoxContainer = pair[1].get_child(0)
	head.get_child(0).add_theme_font_size_override("font_size",13)
	var dots = app._label(head,"● ".repeat(step)+"◉ "+"● ".repeat(3-step),12)
	head.move_child(dots,1)
	dots.autowrap_mode = TextServer.AUTOWRAP_OFF
	dots.size_flags_horizontal = Control.SIZE_SHRINK_END
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var demo = preload("res://intro_demo(인트로 시연).gd").new()
	demo.lesson = step
	demo.effects = app.board.effects
	demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pair[1].add_child(demo)
	var title = app._label(pair[1],"1. 배치 · 기본 배치로 시작하거나 바꿀 수 있어요" if step==0 else str(spec.title),19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 46
	var caption = app._rich(pair[1],_intro_caption(str(spec.frames[0].cap),step),14)
	caption.custom_minimum_size.y = 44
	demo.caption_changed.connect(func(text):
		caption.text = _intro_caption(text,step).replace("<b>","[b]").replace("</b>","[/b]")
		caption.modulate.a = 0
		app.create_tween().tween_property(caption,"modulate:a",1,.4))
	var nav = HFlowContainer.new()
	nav.alignment = FlowContainer.ALIGNMENT_CENTER
	pair[1].add_child(nav)
	if step>0: app._button(nav,"← 이전",func(): pair[0].queue_free(); app._intro(step-1))
	if step<3: app._button(nav,"다음 →",func(): pair[0].queue_free(); app._intro(step+1))
	elif app.room.is_empty():
		app._button(nav,"직접 조작하며 배우기",func(): pair[0].queue_free(); app._tutorial(),"primary")
		app._button(nav,"바로 쉬움 봇 대국",func(): pair[0].queue_free(); await app._join({"vs_bot":true,"level":"easy"}))
		app._button(nav,"나중에",pair[0].queue_free)
	else: app._button(nav,"알겠어요",pair[0].queue_free)
	app._rich(pair[1],"기물별 행마·능력은 왼쪽 사이드바 <b>기물 설명</b>에서, 이 안내는 거기 <b>처음 안내 다시 보기</b>로 언제든 다시 볼 수 있어요.",12)

func _effect_preview() -> void:
	var pair = app._small_window("이펙트 미리보기",460,530)
	var demo = preload("res://fx_layer(파티클·전투 이펙트).gd").new()
	demo.preview = true
	demo.cols = 8
	demo.custom_minimum_size = Vector2(288,288)
	demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pair[1].add_child(demo)
	var buttons = HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_CENTER
	pair[1].add_child(buttons)
	var specs = [
		["포획",{"type":"capture","cells":[[3,4]]}],
		["저격",{"type":"fire","cells":[[1,6]],"from":[6,1]}],
		["돌파",{"type":"barrage","cells":[[4,3],[4,4],[4,5],[4,6]],"from":[4,2]}],
		["스캔",{"type":"scan","cells":[[2,4],[2,5],[3,4],[3,5]],"extra":[[2,5]]}],
		["킹 처치",{"type":"kill","cells":[[3,4]],"from":[7,0]}],
		["승리",{"type":"victory"}],["패배",{"type":"defeat"}],["무승부",{"type":"drawend"}]]
	for spec in specs: app._button(buttons,spec[0],func(): demo.play(spec[1]); app.audio.cue(spec[1].type))
	app._label(pair[1],"보드 위 레이어에서 재생되는 파티클 연출입니다. 브라우저의 '동작 줄이기'가 켜져 있으면 최소 연출로 나옵니다.",12)

func _intro_caption(text: String,step: int) -> String:
	if step==0 and "배치" in text:
		return "기본 배치로 시작하거나 내 진영 3줄 안에서 바꿀 수 있어요. 준비가 되면 <b>준비 완료</b>를 누르세요."
	return text

