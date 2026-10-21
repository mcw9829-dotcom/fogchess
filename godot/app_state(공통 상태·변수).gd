extends Control
## Shared scene/session state. Feature modules read/write this through their app reference.
const Net = preload("res://net(서버 요청·응답).gd")
const Board = preload("res://board(보드·기물·이동 연출).gd")
const Audio = preload("res://audio(배경음·효과음).gd")
const NAMES := {"K":"킹", "Q":"퀸", "R":"전차", "B":"비숍", "N":"나이트", "P":"폰"}
var api: Node
var board: Control
var audio: Node
var prefs := ConfigFile.new()
var room := ""
var token := ""
var seat := ""
var session := ""
var me: Dictionary = {}
var view: Dictionary = {}
var selection: Dictionary = {}
var selection_icon: TextureRect
var action_hint: Label
var action_details: Label
var action_details_button: Button
var moves: Dictionary = {}
var mode := "move"
var action_menu: Control
var enemy_counts: Label
var enemy_icons: HFlowContainer
var opponent_line: Label
var self_line: Label
var utility_actions: Control
var busy := false
var polling := false
var matching := false
var generation := 0
var pending_fx: Dictionary = {}
var last_fx := 0
var last_turn := -1
var reveal := false
var match_window: Window
var match_box: VBoxContainer
var match_body: VBoxContainer
var match_rejoin_at := -6000
var result_sub: Label
var result_actions: VBoxContainer
var result_signature := ""
var original_fonts: Dictionary = {}
var match_data: Dictionary = {}
var rail_panel: PanelContainer
var rail_version: Button
var rail_spacer: Control
var profile_button: Button
var nav_buttons: Array[Button] = []
var subpage: VBoxContainer
var game_left: VBoxContainer
var page_scroll: ScrollContainer
var ranking_subtitle: Label
var room_label: Label
var invite_row: HBoxContainer
var invite_field: LineEdit
var opponent_panel: PanelContainer
var my_panel: PanelContainer
var status_label: Label
var coach_label: Label
var sound_button: Button
var feed_box: VBoxContainer
var feed_signature := ""
var result_panel: PanelContainer
var app_title: Label
var mode_cards: Array[Button] = []
var shell: BoxContainer
var rail: BoxContainer
var landing: BoxContainer
var ranking: VBoxContainer
var menu: VBoxContainer
var home: VBoxContainer
var game: VBoxContainer
var split: BoxContainer
var controls: VBoxContainer
var controls_scroll: ScrollContainer
var account_label: Label
var state_label: Label
var players_label: Label
var selection_label: Label
var notice: Label
var history_label: Label
var result_label: Label
var match_label: Label
var code_field: LineEdit
var guest_field: LineEdit
var level: OptionButton
var setup_controls: HBoxContainer
var over_controls: HBoxContainer
var ready_button: Button
var resign_button: Button
var reveal_button: Button
var accept_button: Button
var cancel_match: Button
var promote_window: Window
var responsive := false
var testing := "--smoke" in OS.get_cmdline_user_args()


var cancel_selection_button: Button

# Match HUD and independently scrolling sidebar.
var side_panel: VBoxContainer
var clock_label: Label
var turn_meta: Label
var series_label: Label
var warning_label: Label
var history_button: Button
var result_score: Label
