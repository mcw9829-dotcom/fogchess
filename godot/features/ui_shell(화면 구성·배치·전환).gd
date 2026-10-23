extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app
var setup_ui
var match_header: PanelContainer
var presence_slot: HBoxContainer
var presence_cell: MarginContainer
var clock_cell: MarginContainer
var state_group: VBoxContainer
var opponent_rating: Label
var presence_divider: VSeparator
var self_panel: PanelContainer
var content_margin: MarginContainer
var self_row: HBoxContainer

func _init(context: Control) -> void:
	app = context

func _build() -> void:
	app.get_viewport().gui_embed_subwindows = true
	app.shell = BoxContainer.new()
	app.shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.shell.add_theme_constant_override("separation",0)
	app.add_child(app.shell)
	app.rail_panel = PanelContainer.new()
	app.rail_panel.custom_minimum_size.x = 208
	app.shell.add_child(app.rail_panel)
	app.rail = BoxContainer.new()
	app.rail.vertical = true
	app.rail.add_theme_constant_override("separation",4)
	app.rail_panel.add_child(app.rail)
	var brand = app._nav(app.rail,"안개전장","king",app._navigation_home)
	brand.custom_minimum_size.y = 46
	brand.add_theme_font_override("font",app._original_font(700))
	app.rail_version = app._button(app.rail,"패치노트",app._patchnotes)
	app.rail_version.add_theme_font_size_override("font_size",11)
	app.rail_version.flat = true
	app.rail_version.custom_minimum_size.y = 26
	app._nav(app.rail,"플레이","play",app._navigation_home)
	app._nav(app.rail,"기물 설명","book",app._help)
	app._nav(app.rail,"리더보드","trophy",app._leaderboard)
	app._nav(app.rail,"피드백","chat",app._feedback)
	app._nav(app.rail,"설정","settings",app._settings)
	app.rail_spacer = Control.new()
	app.rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.rail.add_child(app.rail_spacer)
	app.profile_button = app._nav(app.rail,"게스트\n로그인 · 회원가입","user",app._account)
	app.profile_button.custom_minimum_size.y = 54
	var margin = MarginContainer.new()
	content_margin = margin
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,22)
	app.shell.add_child(margin)
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation",6)
	margin.add_child(root)
	app.page_scroll = ScrollContainer.new()
	app.page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(app.page_scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.page_scroll.add_child(body)
	app.home = VBoxContainer.new()
	app.home.alignment = BoxContainer.ALIGNMENT_CENTER
	app.home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(app.home)
	var home_center = CenterContainer.new()
	app.home.add_child(home_center)
	app.landing = BoxContainer.new()
	app.landing.add_theme_constant_override("separation",40)
	home_center.add_child(app.landing)
	app.ranking = app._card(app.landing,"")
	app.ranking.get_parent().custom_minimum_size.x = 380
	var ranking_header = HBoxContainer.new()
	app.ranking.add_child(ranking_header)
	app._icon(ranking_header,"trophy",22)
	app._label(ranking_header,"리더보드",17)
	app.ranking_subtitle = app._label(ranking_header,"레이팅 순",11)
	app.ranking_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	app.ranking.add_child(HSeparator.new())
	var ranks = VBoxContainer.new()
	ranks.name = "Ranks"
	ranks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.ranking.add_child(ranks)
	app._label(ranks,"순위를 불러오는 중…",13)
	app.ranking.add_child(HSeparator.new())
	var foot = HBoxContainer.new()
	app.ranking.add_child(foot)
	app.account_label = app._label(foot,"로그인하면 내 순위가 여기에 표시돼요",12)
	var more = app._button(foot,"전체 순위 · 티어 →",app._leaderboard)
	more.add_theme_font_size_override("font_size",11)
	app.menu = VBoxContainer.new()
	app.menu.custom_minimum_size.x = 400
	app.menu.add_theme_constant_override("separation",12)
	app.landing.add_child(app.menu)
	var logo = HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	app.menu.add_child(logo)
	app._icon(logo,"king",32)
	app.app_title = app._label(logo,"안개전장 체스",30)
	app.app_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	app.app_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var subtitle = app._label(app.menu,"WW1 Fog Chess",13)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.custom_minimum_size.y = 28
	app._mode_card(app.menu,"랭크 매칭","비슷한 레이팅의 상대와 대국 · 로그인 필요","play",func(): await app._match_command("join"),true)
	app._mode_card(app.menu,"로비 게임 만들기","친구와 사설 방에서 대전(초대 링크) · 레이팅 미반영","people",func(): await app._join({}))
	app._mode_card(app.menu,"리플레이","종료 대국의 기보 · 한 수씩 / 자동 재생","replay",app.replay.menu)
	app._mode_card(app.menu,"대국 관전","방 코드로 관전 · 전체 보드 3분 지연 중계","watch",app.spectating.menu)
	app._mode_card(app.menu,"친구 방 참가","친구가 준 방 코드로 입장 · 레이팅 미반영","join",app._friend_menu)
	app._mode_card(app.menu,"컴퓨터와 대국","쉬움 · 보통 · 어려움 · 이기면 레이팅 상승, 져도 하락 없음","computer",app._bot_menu)
	app._mode_card(app.menu,"혼자 연습","백·흑 번갈아 연습 · 레이팅 미반영","target",func(): await app._join({"solo":true}))
	app._mode_card(app.menu,"설정","효과음 · 배경음악 · 다크/화이트 · 색약","settings",app._settings)
	app.guest_field = app._field(app.home,"게스트 닉네임",str(app.prefs.get_value("settings","nickname","플레이어")))
	app.guest_field.hide()
	app.level = OptionButton.new()
	for item in ["쉬움","보통","어려움"]: app.level.add_item(item)
	app.home.add_child(app.level)
	app.level.hide()
	app.code_field = app._field(app.home,"방 코드")
	app.code_field.hide()
	app.match_label = app._label(app.home,"",15)
	app.match_label.hide()
	var match_buttons = HBoxContainer.new()
	app.home.add_child(match_buttons)
	app.accept_button = app._button(match_buttons,"대전 수락",func(): await app._match_command("accept"))
	app.cancel_match = app._button(match_buttons,"매칭 취소 / 거절",func(): await app._match_command("cancel"))
	app.accept_button.hide()
	app.cancel_match.hide()
	app.subpage = VBoxContainer.new()
	app.subpage.alignment = BoxContainer.ALIGNMENT_CENTER
	app.subpage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.subpage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	app.subpage.custom_minimum_size.x = 400
	app.subpage.add_theme_constant_override("separation",12)
	body.add_child(app.subpage)
	app.subpage.hide()
	app.game = VBoxContainer.new()
	app.game.add_theme_constant_override("separation",12)
	app.game.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(app.game)
	app.game.hide()
	app.split = BoxContainer.new()
	app.split.add_theme_constant_override("separation",22)
	app.game.add_child(app.split)
	app.game_left = VBoxContainer.new()
	app.game_left.add_theme_constant_override("separation",6)
	app.split.add_child(app.game_left)
	app.match_ui.build_header()
	app.board = app.Board.new()
	app.board.tapped.connect(app._tap)
	app.board.dragged.connect(app._drag)
	app.board.selection_cancelled.connect(app._clear_selection)
	app.board.colorblind = bool(app.prefs.get_value("settings","colorblind",false))
	app.board.effects = bool(app.prefs.get_value("settings","effects",true))
	app.game_left.add_child(app.board)
	app.match_ui.build_footer()
	app.action_menu = preload("res://action_menu(기물 행동 메뉴).gd").new()
	app.board.add_child(app.action_menu)
	app.action_menu.chosen.connect(app._choose_action)
	app.action_menu.previewed.connect(app.piece_input._preview_action)
	app.board.resized.connect(app.piece_input._reposition_actions.call_deferred)
	app.result_panel = PanelContainer.new()
	app.result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	app.board.add_child(app.result_panel)
	var result_box = VBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.add_theme_constant_override("separation",12)
	app.result_panel.add_child(result_box)
	app.result_label = app._label(result_box,"",34)
	app.result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.result_score = app._label(result_box,"",26)
	app.result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.result_sub = app._label(result_box,"",14)
	app.result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app.result_actions = VBoxContainer.new()
	app.result_actions.add_theme_constant_override("separation",8)
	result_box.add_child(app.result_actions)
	app.result_panel.hide()
	app.side_panel = VBoxContainer.new()
	app.side_panel.add_theme_constant_override("separation",12)
	app.split.add_child(app.side_panel)
	app.controls_scroll = ScrollContainer.new()
	app.controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.controls_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	app.controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.side_panel.add_child(app.controls_scroll)
	app.controls = VBoxContainer.new()
	app.controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.controls.add_theme_constant_override("separation",12)
	app.controls_scroll.add_child(app.controls)
	var room_card = app.match_ui.card(app.controls)
	app.room_label = app._label(room_card,"",12)
	app.invite_row = HBoxContainer.new()
	room_card.add_child(app.invite_row)
	app.invite_field = app._field(app.invite_row,"초대 링크")
	app.invite_field.editable = false
	var copy_invite = app._button(app.invite_row,"복사",func(): pass)
	copy_invite.pressed.connect(func():
		DisplayServer.clipboard_set(app.invite_field.text)
		if DisplayServer.clipboard_get()==app.invite_field.text:
			app.ui_motion.confirm(copy_invite)
			app._message("초대 링크를 복사했습니다.")
		else: app._message("초대 링크를 복사하지 못했습니다."))
	var player_card = app.match_ui.card(app.controls)
	app.opponent_panel = preload("res://player_card(플레이어 정보 카드).gd").new()
	player_card.add_child(app.opponent_panel)
	app.my_panel = preload("res://player_card(플레이어 정보 카드).gd").new()
	player_card.add_child(app.my_panel)
	app.players_label = app._label(player_card,"",12)
	app.status_label = app._label(player_card,"",14)
	var action_card = app.match_ui.card(app.controls)
	app.setup_controls = HBoxContainer.new()
	action_card.add_child(app.setup_controls)
	app._button(app.setup_controls,"기본 배치",func(): await app._act({"type":"autoplace","mode":"default"}))
	app._button(app.setup_controls,"무작위",func(): await app._act({"type":"autoplace","mode":"random"}))
	app.ready_button = app._button(action_card,"준비 완료",func(): await app._act({"type":"ready","value":not app.view.get("ready",false)}),"primary")
	app.reveal_button = app._button(action_card,"안개 걷힘 OFF",func(): app.reveal = not app.reveal; await app._poll())
	app.reveal_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	app.match_ui.build_selection(action_card)
	var actions = HFlowContainer.new()
	app.utility_actions = actions
	action_card.add_child(actions)
	app.sound_button = app._button(actions,"소리 켜짐",app._toggle_sound)
	app.resign_button = app._button(actions,"기권",func(): app.game_session.resign_prompt(),"danger")
	app._button(actions,"나가기",app._leave_prompt).name = "LeaveMatch"
	app.coach_label = app._label(action_card,"",16)
	app.coach_label.add_theme_color_override("font_color",Color("#eed29a"))
	app.action_hint = app._label(action_card,"",13)
	app.action_hint.set_meta("match_muted",true)
	app.action_hint.add_theme_color_override("font_color",app.ui_components._palette().muted)
	app.action_details = app._label(action_card,"",12)
	app.action_details.hide()
	app.over_controls = HBoxContainer.new()
	action_card.add_child(app.over_controls)
	app._button(app.over_controls,"재대결 제안 / 수락",func(): await app._act({"type":"rematch"}))
	app._button(app.over_controls,"거절",func(): await app._act({"type":"rematch_decline"}))
	setup_ui = preload("res://features/setup_ui(배치 준비 시각 안내).gd").new(app)
	setup_ui.build(action_card)
	var log_card = app.match_ui.card(app.controls,"킬로그")
	log_card.get_child(0).add_theme_font_size_override("font_size",12)
	app.feed_box = VBoxContainer.new()
	log_card.add_child(app.feed_box)
	app.enemy_counts = app._label(log_card,"",12)
	app.enemy_icons = HFlowContainer.new()
	app.enemy_icons.add_theme_constant_override("h_separation",12)
	log_card.add_child(app.enemy_icons)
	app.match_ui.build_history(app.controls)
	app.chat.build()
	app.match_ui.build_mobile_actions()
	# Reserve one line so server messages cannot resize the board mid-turn.
	var notice_slot := Control.new()
	notice_slot.custom_minimum_size.y = 22
	root.add_child(notice_slot)
	app.notice = app._label(notice_slot,"",13)
	app.notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.notice.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app.notice.hide()
	app.spectating.build()
	app.replay.build()
	app._load_home_ranks.call_deferred()
	app.game_ux.build(root)
	app.game_left.minimum_size_changed.connect(app._layout.call_deferred)

func _grid_panel(parent: Node) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.theme_type_variation = "MatchGridPanel"
	parent.add_child(panel)
	return panel

func _grid_cell(parent: Node, expand: bool=false) -> MarginContainer:
	var cell = MarginContainer.new()
	for edge in ["left","right"]: cell.add_theme_constant_override("margin_"+edge,10)
	for edge in ["top","bottom"]: cell.add_theme_constant_override("margin_"+edge,8)
	if expand: cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(cell)
	return cell

func _grid_divider(parent: Node, vertical: bool=false) -> Separator:
	var line: Separator = VSeparator.new() if vertical else HSeparator.new()
	line.theme_type_variation = "MatchGridVertical" if vertical else "MatchGridHorizontal"
	line.add_theme_constant_override("separation",1)
	parent.add_child(line)
	return line

func set_audience_visible(value: bool) -> void:
	presence_cell.visible = value
	if is_instance_valid(presence_divider): presence_divider.visible = value

func _layout() -> void:
	for child in app.get_children():
		if child is Window and child.has_meta("preferred_size"):
			var preferred: Vector2i = child.get_meta("preferred_size")
			child.min_size = Vector2i(mini(320,int(app.size.x)-24),mini(280,int(app.size.y)-24))
			child.size = Vector2i(mini(preferred.x,int(app.size.x)-24),mini(preferred.y,int(app.size.y)-24))
			child.position = Vector2i((app.size-Vector2(child.size))/2)
	if not is_instance_valid(app.split): return
	var narrow = app.size.x <= 760
	app.responsive = app.size.x < 1140
	app.shell.vertical = narrow
	app.rail.vertical = not narrow
	app.rail_panel.custom_minimum_size = Vector2(0,56) if narrow else Vector2(208,0)
	app.rail_version.visible = not narrow
	app.rail_spacer.visible = not narrow
	for button in app.nav_buttons:
		button.text = "" if narrow else ("       " if button.has_meta("original_icon") else "")+str(button.get_meta("nav_label"))
		if button.has_meta("original_icon"):
			var art: Control = button.get_meta("original_icon")
			art.set_anchors_and_offsets_preset(Control.PRESET_CENTER if narrow else Control.PRESET_CENTER_LEFT)
			art.offset_left = -13 if narrow else 12
			art.offset_right = art.offset_left+26
			art.offset_top = -13
			art.offset_bottom = 13
		button.custom_minimum_size.x = 42 if narrow else 0
		button.custom_minimum_size.y = 40 if narrow else 46
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if narrow else HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width",26)
	app.profile_button.text = "" if narrow else "       "+("게스트\n       로그인 · 회원가입" if app.me.is_empty() else "%s\n       %d점 · 전적 보기" % [app.me.name,int(app.me.rating)])
	app.rail_panel.visible = not app.game.visible
	var page_padding := 16 if app.game.visible else 22
	for edge in ["left","right","top","bottom"]: content_margin.add_theme_constant_override("margin_"+edge,page_padding)
	var available = maxf(260,app.size.x-(0 if narrow or app.game.visible else 208)-page_padding*2)
	app.landing.vertical = available<820
	app.landing.add_theme_constant_override("separation",20 if app.landing.vertical else 40)
	var menu_width = minf(400,available)
	app.menu.custom_minimum_size.x = menu_width
	app.ranking.get_parent().custom_minimum_size.x = menu_width if app.landing.vertical else 380
	app.landing.move_child(app.ranking.get_parent(),1 if app.landing.vertical else 0)
	app.subpage.custom_minimum_size.x = menu_width
	app.split.vertical = available<780
	# Mobile uses one page scroll; desktop keeps the bounded information rail.
	app.controls_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if app.split.vertical else ScrollContainer.SCROLL_MODE_AUTO
	app.controls_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if app.split.vertical else Control.SIZE_EXPAND_FILL
	app.match_ui.layout_mobile_actions()
	app.match_ui.mode_label.visible = app.size.x>=480
	if is_instance_valid(app.spectating.flip_button):
		app.spectating.flip_button.text = "↕" if available<400 else "보드 뒤집기"
		app.spectating.flip_button.tooltip_text = "보드 뒤집기"
	# Measure the actual chrome so cards, warnings and replay controls cannot push
	# the board off a desktop window after changing their parent containers.
	var frame_chrome: float = page_padding*2.0+app.match_ui.chrome.get_combined_minimum_size().y+app.game.get_theme_constant("separation")+28
	var chrome_height := frame_chrome
	for child in app.game_left.get_children():
		if child==app.board or not child.visible: continue
		chrome_height += child.get_combined_minimum_size().y+app.game_left.get_theme_constant("separation")
	# Square cells and original art proportions, sized from the actual viewport.
	# A wide browser can exceed the old 640 px cap; a short one must still fit.
	var board_width = available if app.split.vertical else minf(available-302,maxf(280,app.size.y-chrome_height))
	app.board.custom_minimum_size = Vector2(board_width,board_width)
	app.side_panel.custom_minimum_size = Vector2(board_width if app.split.vertical else 280,0 if app.split.vertical else board_width+chrome_height-frame_chrome)
	app.controls_scroll.custom_minimum_size = Vector2(0,0)
	app.game_left.custom_minimum_size.x = board_width
	for card in app.mode_cards:
		if is_instance_valid(card): card.custom_minimum_size.y = maxf(76,card.get_node("ModeCardContent").get_combined_minimum_size().y)
	app.game_ux.update_scroll_bar.call_deferred()
	app._nav_active("설정" if app.subpage.visible and app.subpage.get_child_count()>0 and app.subpage.get_child(0).text=="설정" else "플레이")

func _navigation_home() -> void:
	if app.room.is_empty():
		app.subpage.hide()
		app.home.show()
		app.ui_motion.enter_screen.call_deferred(app.home)
		app.game_ux.refresh_learning()
		app._nav_active("플레이")
	else:
		app.subpage.hide()
		app.game.show()
		app._nav_active("플레이")

func _subscreen(title: String, description: String="") -> VBoxContainer:
	for child in app.subpage.get_children():
		app.subpage.remove_child(child)
		child.queue_free()
	app.home.hide()
	app.game.hide()
	app.subpage.show()
	app.ui_motion.enter_screen.call_deferred(app.subpage)
	app.page_scroll.scroll_vertical = 0
	var heading = app._label(app.subpage,title,30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not description.is_empty():
		var sub = app._label(app.subpage,description,13)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.custom_minimum_size.y = 34
	return app.subpage

func _nav_active(text: String) -> void:
	for button in app.nav_buttons:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0,0,0,0)
		style.set_corner_radius_all(12)
		style.content_margin_left = 4 if app.size.x<=760 else 12
		style.content_margin_right = 4 if app.size.x<=760 else 12
		button.add_theme_stylebox_override("normal",style)
		if button.get_meta("nav_label")==text: app.ui_motion.select_navigation(button)
		button.add_theme_color_override("font_color",Color("#241d14") if button.get_meta("nav_label")==text else (Color("#453c32") if app.prefs.get_value("settings","light",false) else Color("#b6b0a6")))
