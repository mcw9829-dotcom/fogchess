extends Node
## Fixed lobby status slots: queue above the page, owned active game below it.
var app
var queue_card: PanelContainer
var queue_text: Label
var cancel: Button
var resume_card: PanelContainer
var resume_note: Label
var resume: Button
var active: Dictionary = {}
var waiting: Dictionary = {}
var requested := false
var session_seen := ""
var elapsed := 0.0
var signature := ""
var palette_key := ""

func _init(context: Control): app=context

func build():
	var stack=app.page_scroll.get_parent()
	queue_card=PanelContainer.new();queue_card.name="LobbyQueueStatus"
	queue_card.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	stack.add_child(queue_card);stack.move_child(queue_card,0)
	var queue_column=VBoxContainer.new();queue_card.add_child(queue_column)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);queue_column.add_child(row)
	queue_text=app._label(row,"",14);queue_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	queue_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	cancel=app._button(row,"취소",func(): await app._match_command("cancel"))
	cancel.custom_minimum_size=Vector2(64,44)
	resume_card=PanelContainer.new();resume_card.name="LobbyResumeStatus"
	resume_card.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	stack.add_child(resume_card)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",6);resume_card.add_child(column)
	resume_note=app._label(column,"",12);resume_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	resume=app._button(column,"진행 중인 대국 이어하기",resume_game,"primary")
	resume.name="ResumeActiveGame";resume.custom_minimum_size.y=48
	queue_card.hide();resume_card.hide()
	app.resized.connect(layout)
	layout()
	_sync()

func set_active(value: Variant):
	active=value.duplicate(true) if value is Dictionary else {}
	_sync()

func set_queue(value: Dictionary):
	waiting=value.duplicate(true) if value.get("state") in ["waiting","found"] else {}
	_sync()

func refresh_active():
	if requested or app.session.is_empty(): return
	requested=true
	var session: String=app.session
	var result: Dictionary=await app.api.request("/me/active-game",{"session":session})
	requested=false
	if session!=app.session: return
	if result.get("ok",false): set_active(result.get("activeGame"))
	elif not result.get("network_error",false): set_active(null)

func resume_game():
	if app.busy or app.matching or active.is_empty(): return
	# Refresh first: never recreate a stale/deleted room from a cached room code.
	await refresh_active()
	if active.is_empty(): app._message("대국이 종료되었습니다."); return
	await app._join({"room":str(active.room),"resume":true})

func _process(delta: float):
	if not is_instance_valid(queue_card): return
	if session_seen!=app.session:
		session_seen=app.session;set_active(null);elapsed=10.0
	elapsed+=delta
	if elapsed>=10.0 and app.home.visible and app.room.is_empty():
		elapsed=0.0;refresh_active()
	_sync()

func _sync():
	if not is_instance_valid(queue_card): return
	var show_queue: bool=app.matching and not waiting.is_empty()
	var show_resume: bool=app.home.visible and app.room.is_empty() and not active.is_empty() and not app.matching
	var next=str([show_queue,show_resume,waiting,active,app.busy,app.game.visible,app.matchmaking.command_busy,app.prefs.get_value("settings","light",false)])
	if next==signature: return
	signature=next
	var changed: bool=queue_card.visible!=show_queue or resume_card.visible!=show_resume
	queue_card.visible=show_queue;resume_card.visible=show_resume
	var seconds: int=int(waiting.get("waited",0))
	queue_text.text="랭크 매칭 중  %02d:%02d\n상대를 찾고 있어요" % [seconds/60,seconds%60]
	if waiting.get("state")=="found": queue_text.text="랭크 상대 발견\n수락을 기다리고 있어요"
	resume_note.text="%s · %s" % [{"practice":"매칭 대기용 연습","rank":"랭크 대국","bot":"컴퓨터 대국","friend":"친구 대국"}.get(active.get("mode",""),"진행 중인 대국"),str(active.get("opponent","상대"))]
	cancel.disabled=app.matchmaking.command_busy;resume.disabled=app.busy
	layout()
	if changed: app._layout.call_deferred()

func layout():
	if not is_instance_valid(queue_card): return
	var width: float=minf(380,maxf(240,app.size.x-40))
	for card in [queue_card,resume_card]: card.custom_minimum_size.x=width
	var colors: Dictionary=app.ui_components._palette()
	for card in [queue_card,resume_card]:
		var style=StyleBoxFlat.new();style.bg_color=colors.surface;style.border_color=colors.border
		style.set_border_width_all(1);style.set_corner_radius_all(12)
		for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,10.0)
		card.add_theme_stylebox_override("panel",style)
	queue_text.add_theme_color_override("font_color",colors.text)
	resume_note.add_theme_color_override("font_color",colors.muted)

func reserved_height() -> float:
	var result:=0.0
	for card in [queue_card,resume_card]:
		if is_instance_valid(card) and card.visible: result+=card.get_combined_minimum_size().y+6
	return result
