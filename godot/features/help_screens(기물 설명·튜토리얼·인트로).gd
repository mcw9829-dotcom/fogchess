extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

func _init(context: Control) -> void:
	app = context

func _help() -> void:
	var pair = app._small_window("기물 설명",1230,540)
	pair[0].set_meta("suppress_hover_tooltips",true)
	var header: HBoxContainer = pair[1].get_child(0)
	var title: Label = header.get_child(0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Balance the close button so the title sits on the window centerline.
	var balance := Control.new()
	balance.custom_minimum_size.x = header.get_child(1).get_combined_minimum_size().x
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(balance)
	header.move_child(balance,0)
	pair[1].add_theme_constant_override("separation",8)
	var links = HFlowContainer.new()
	links.alignment = FlowContainer.ALIGNMENT_CENTER
	pair[1].add_child(links)
	app._button(links,"처음 안내(1분) 다시 보기",func(): pair[0].queue_free(); app._intro())
	app._button(links,"직접 배우기 · 왕 찾기 미션",func(): pair[0].queue_free(); app._tutorial())
	app._rich(pair[1],"[center]기물 카드에 <b>마우스를 올리면</b>(모바일은 <b>탭</b>) 행마 → 공격 → 능력 순으로 애니메이션을 보여줍니다. 이펙트와 효과음은 설정을 따릅니다.[/center]",12)
	var nav = HBoxContainer.new()
	pair[1].add_child(nav)
	var prev = app._button(nav,"◀",func(): pass)
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 386
	nav.add_child(scroll)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	scroll.add_child(row)
	var next = app._button(nav,"▶",func(): pass)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var demos: Array = []
	var cards: Array = []
	for spec in preload("res://original_demo(원본 시연 재현).gd").scenes().guide:
		var card = app._card(row,"")
		var panel: Control = card.get_parent()
		panel.custom_minimum_size.x = 212
		card.add_theme_constant_override("separation",5)
		cards.append(panel)
		panel.focus_mode = Control.FOCUS_ALL
		panel.tooltip_text = "마우스를 올리거나 클릭하면 시연 재생 · Enter로도 재생"
		var playback = app._label(card,"시연 대기",12)
		playback.name = "PlaybackStatus"
		playback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		playback.custom_minimum_size.y = 22
		var demo = preload("res://guide_demo(설명용 시연).gd").new()
		demo.kind = spec.t
		demo.effects = app.board.effects
		demo.sound = app.audio.cue
		demo.host = panel
		demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.add_child(demo)
		demos.append(demo)
		var update_status = func(_playing: bool=false):
			var colors: Dictionary = app.ui_components._palette()
			var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
			style.set_border_width_all(2)
			style.border_color = colors.accent.lightened(.22) if demo.running else colors.border.darkened(.15)
			style.bg_color = colors.surface.lerp(colors.accent,.07) if demo.running else colors.surface
			panel.add_theme_stylebox_override("panel",style)
			playback.text = "▶ 재생 중 · "+str(demo.state.get("phase","행마")) if demo.running else "시연 대기"
			playback.add_theme_color_override("font_color",colors.text if demo.running else colors.muted)
		update_status.call()
		demo.playback_changed.connect(update_status)
		demo.caption_changed.connect(func(_text): update_status.call())
		demo.activated.connect(func():
			for other in demos:
				if other!=demo and is_instance_valid(other): other.stop())
		panel.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT: demo.start()
			elif event.is_action_pressed("ui_accept"): demo.start(); panel.accept_event())
		panel.mouse_entered.connect(demo.start)
		panel.mouse_exited.connect(func():
			if not Rect2(Vector2.ZERO,panel.size).has_point(panel.get_local_mouse_position()): demo.stop())
		var label = app._label(card,spec.nm,14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for key in ["move","atk","abil"]:
			if spec.has(key):
				var description = app._rich(card,"[b]"+{"move":"행마","atk":"공격","abil":"능력"}[key]+"[/b]  "+str(spec[key]),12)
				description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var navigate = func(direction: int): scroll.scroll_horizontal = clampi(scroll.scroll_horizontal+direction*224,0,ceili(scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page))
	prev.pressed.connect(func(): navigate.call(-1))
	next.pressed.connect(func(): navigate.call(1))
	scroll.get_h_scroll_bar().value_changed.connect(func(value):
		prev.disabled = value<=0
		next.disabled = value>=scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page-1)
	prev.disabled = true
	var chips = HFlowContainer.new()
	pair[1].add_child(chips)
	chips.visible = app.size.x<540
	prev.visible = app.size.x>=540
	next.visible = app.size.x>=540
	for i in range(6): app._button(chips,["폰","나이트","비숍","전차","퀸","킹"][i],func(): scroll.scroll_horizontal = i*224; demos[i].start())

func _tutorial() -> void:
	for child in app.get_children():
		if child is Window and child.visible: child.hide()
	if app.busy or app.matching: return
	var window = Window.new()
	window.title = "직접 배우기 · 왕 찾기 미션"
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	app.add_child(window)
	var tutorial = preload("res://tutorial(튜토리얼 진행).gd").new()
	var saved = int(app.prefs.get_value("settings","tutorial_step",0))
	tutorial.step = 0 if saved>=3 else saved
	tutorial.progress_changed.connect(func(value): app.prefs.set_value("settings","tutorial_step",value); app._save(); app.game_ux.refresh_learning())
	tutorial.start_game.connect(func(): window.queue_free(); await app._join({"vs_bot":true,"level":"easy"}))
	window.add_child(tutorial)
	window.popup_centered(Vector2i(mini(int(app.size.x)-24,1060),mini(int(app.size.y)-24,720)))

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
