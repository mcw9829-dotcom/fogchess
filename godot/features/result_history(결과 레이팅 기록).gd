extends RefCounted
var app
var box: VBoxContainer
var status: Label
var chart
var retry: Button
var frame: MarginContainer
var request_key := ""
var generation := 0

func _init(context: Control) -> void: app = context

func build() -> void:
	box = VBoxContainer.new()
	box.name = "ResultRatingHistory"
	box.add_theme_constant_override("separation",4)
	var parent = app.result_actions.get_parent()
	frame = MarginContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for side in ["left","right"]: frame.add_theme_constant_override("margin_"+side,12)
	parent.add_child(frame)
	parent.move_child(frame,app.result_actions.get_index())
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202a2e")
	style.set_corner_radius_all(10)
	for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,12.0)
	card.add_theme_stylebox_override("panel",style)
	frame.add_child(card)
	card.add_child(box)
	parent.resized.connect(layout)
	app.resized.connect(layout.call_deferred)
	status = app._label(box,"",12)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color",Color("#b8c3c6"))
	chart = preload("res://rating_trend(최근 10판 레이팅).gd").new()
	box.add_child(chart)
	retry = app._button(box,"기록 다시 불러오기",func(): request_key = ""; refresh(),"tertiary")
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.hide()
	layout()

func layout() -> void:
	var parent = app.result_actions.get_parent()
	var available: float = minf(app.size.x-56,app.board.custom_minimum_size.x-24)
	frame.custom_minimum_size.x = minf(460,maxf(0,available))
	var mobile: bool = available < 420
	if (mobile and frame.get_index() < app.result_actions.get_index()) or (not mobile and frame.get_index() > app.result_actions.get_index()):
		parent.move_child(frame,app.result_actions.get_index())

func refresh() -> void:
	if not is_instance_valid(box): build()
	var eligible: bool = not app.session.is_empty() and app.seat != "spectator" and not app.replay.active and not app.view.get("solo",false)
	frame.visible = eligible
	box.visible = eligible
	var key = str([app.room,app.view.get("turnCount"),app.session,app.view.get("settlementPending",false),app.view.get("ratingDelta"),eligible])
	if key == request_key: return
	request_key = key
	generation += 1
	if not eligible: return
	chart.hide()
	retry.hide()
	status.text = "최근 레이팅 대국 · 기록을 불러오는 중…"
	if app.view.get("settlementPending",false):
		status.text = "결과 저장 후 레이팅 기록을 표시합니다."
		return
	_fetch(generation,app.session)

func _fetch(version: int, session: String) -> void:
	var data: Dictionary = await app.api.request("/me/history",{"session":session,"rating_only":true})
	if version != generation or not is_instance_valid(box) or app.session != session or app.view.get("phase") != "over": return
	if not data.get("ok",false):
		status.text = "레이팅 기록을 불러오지 못했어요."
		retry.show()
		return
	chart.set_rows(data.get("rows",[]))
	chart.visible = not chart.rows.is_empty()
	status.text = "최근 레이팅 대국 · 오래된 순" if chart.visible else "아직 레이팅 대국 기록이 없습니다."
