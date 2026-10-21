extends RefCounted
var app
var data: Dictionary = {}
var index := 0
var active := false
var playing := false
var timer: Timer
var bar: VBoxContainer
var bar_panel: PanelContainer
var vision_panel: PanelContainer
var counter: Label
var play_button: Button
var previous_button: Button
var next_button: Button
var return_view: Dictionary = {}
var return_seat := ""
var vision_bar: HBoxContainer
var vision_buttons: Array[Button] = []
var vision := "all"
var transport: Control
var transport_center: HBoxContainer
var close_button: Button
var frame_picker: OptionButton
var previous_event: Button
var next_event: Button

func _init(context: Control) -> void:
	app = context

func build() -> void:
	bar_panel = app.ui_shell._grid_panel(app.game_left)
	app.game_left.move_child(bar_panel,app.ui_shell.self_panel.get_index()+1)
	var bar_cell = app.ui_shell._grid_cell(bar_panel)
	bar = VBoxContainer.new()
	bar.add_theme_constant_override("separation",8)
	bar_cell.add_child(bar)
	bar.visibility_changed.connect(func(): bar_panel.visible = bar.visible)
	counter = app._label(bar,"",13)
	app.ui_shell._grid_divider(bar)
	transport = Control.new()
	bar.add_child(transport)
	close_button = app._button(transport,"닫기",close)
	transport_center = HBoxContainer.new()
	transport.add_child(transport_center)
	previous_button = app._button(transport_center,"◀ 이전",func(): step(-1))
	play_button = app._button(transport_center,"자동 재생",toggle)
	next_button = app._button(transport_center,"다음 ▶",func(): step(1))
	var navigation := HFlowContainer.new()
	navigation.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_child(navigation)
	frame_picker = OptionButton.new()
	frame_picker.custom_minimum_size.x = 170
	frame_picker.clip_text = true
	frame_picker.tooltip_text = "기보 수순을 선택하면 해당 장면으로 이동합니다."
	navigation.add_child(frame_picker)
	frame_picker.item_selected.connect(func(value): seek(value))
	previous_event = app._button(navigation,"◀ 주요 사건",func(): jump_event(-1))
	next_event = app._button(navigation,"주요 사건 ▶",func(): jump_event(1))
	app._button(navigation,"제보 정보 복사",func():
		DisplayServer.clipboard_set(report_context())
		app._message("리플레이 ID·수순·시야를 복사했습니다. 제보 내용에 붙여넣으세요."))
	transport.resized.connect(_transport_layout)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vision_panel = app.ui_shell._grid_panel(app.game_left)
	app.game_left.move_child(vision_panel,app.board.get_index())
	var vision_cell = app.ui_shell._grid_cell(vision_panel)
	vision_bar = HBoxContainer.new()
	vision_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	vision_cell.add_child(vision_bar)
	vision_bar.visibility_changed.connect(func(): vision_panel.visible = vision_bar.visible)
	var vision_label = app._label(vision_bar,"보드 시야",12)
	vision_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	vision_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vision_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for item in [["전체","all"],["백 시야","W"],["흑 시야","B"]]:
		var side: String = item[1]
		var button = app._button(vision_bar,item[0],func(): vision=side; show_frame())
		button.toggle_mode = true
		vision_buttons.append(button)
	vision_bar.hide()
	bar.hide()
	timer = Timer.new()
	timer.wait_time = 1.5
	timer.timeout.connect(_tick)
	app.add_child(timer)

func _transport_layout() -> void:
	var width: float = transport.size.x
	var center_size: Vector2 = transport_center.get_combined_minimum_size()
	var close_size: Vector2 = close_button.get_combined_minimum_size()
	var compact: bool = width < center_size.x+2*(close_size.x+8)
	transport.custom_minimum_size.y = center_size.y+close_size.y+8 if compact else maxf(center_size.y,close_size.y)
	transport_center.size = center_size
	transport_center.position = Vector2(maxf(0,(width-center_size.x)/2),0)
	close_button.size = close_size
	close_button.position = Vector2(0,center_size.y+8 if compact else 0)

func _tick() -> void:
	if not active: timer.stop(); return
	if index<data.frames.size()-1: index+=1
	if index==data.frames.size()-1: playing=false; timer.stop()
	show_frame()

func open(id: String, token: String="") -> void:
	if app.busy or active: return
	app.busy = true
	var response: Dictionary = await app.api.request("/replay?id=%s&token=%s&session=%s" % [id.uri_encode(),token.uri_encode(),app.session.uri_encode()])
	app.busy = false
	if not response.get("ok"): app._report(response); return
	data = response.replay
	if data.get("frames",[]).is_empty(): app._message("재생할 기보가 없습니다."); return
	return_view = app.view.duplicate(true)
	return_seat = app.seat
	active = true
	playing = false
	index = 0
	frame_picker.clear()
	for i in range(data.frames.size()): frame_picker.add_item(_frame_title(i),i)
	vision = "all"
	app.generation += 1
	app.seat = "spectator"
	app.home.hide()
	app.subpage.hide()
	app.game.show()
	app._clear_selection()
	bar.show()
	vision_bar.show()
	app._layout()
	show_frame()

func remember() -> void:
	var id: String = app.view.get("replayId","") if app.view.get("replayId")!=null else ""
	if id.is_empty() or active: return
	var saved: Array = app.prefs.get_value(app.api.base_url,"replays",[])
	for item in saved:
		if item.id==id: return
	saved.push_front({"id":id,"token":app.token,"title":"방 "+app.room+" · "+Time.get_datetime_string_from_system()})
	if saved.size()>100: saved.resize(100)
	app.prefs.set_value(app.api.base_url,"replays",saved)
	app._save()

func menu() -> void:
	var box: VBoxContainer = app._subscreen("저장된 리플레이","이 기기에서 확인한 종료 대국 · 서버에 기보가 저장됩니다.")
	var saved: Array = app.prefs.get_value(app.api.base_url,"replays",[])
	if saved.is_empty(): app._label(box,"대국 종료 후 리플레이가 여기에 표시됩니다.")
	for item in saved:
		app._button(box,str(item.title),func(): await open(str(item.id),str(item.token)))
	app._button(box,"← 뒤로",app._navigation_home)

func step(amount: int) -> void:
	playing = false
	timer.stop()
	index = clampi(index+amount,0,data.frames.size()-1)
	show_frame()

func seek(value: int) -> void:
	step(value-index)

func _is_event(value: int) -> bool:
	if value<=0 or value>=data.frames.size(): return false
	var frame: Dictionary = data.frames[value]
	var action: Variant = frame.get("action")
	if action is Dictionary and action.get("action") in ["fire","barrage","scan","promote","resign"]: return true
	var previous: Dictionary = data.frames[value-1].get("pieces",{})
	for pid in frame.get("pieces",{}):
		if previous.get(pid,{}).get("alive",false) and not frame.pieces[pid].get("alive",false): return true
	return frame.view.get("phase")=="over"

func _event_index(direction: int) -> int:
	var target := index+direction
	while target>=0 and target<data.frames.size():
		if _is_event(target): return target
		target+=direction
	return -1

func jump_event(direction: int) -> void:
	var target := _event_index(direction)
	if target>=0: seek(target)

func _square(rc: Variant) -> String:
	if not rc is Array or rc.size()!=2 or rc[0]==null or rc[1]==null: return ""
	return String.chr(97+int(rc[1]))+str(int(rc[0])+1)

func _frame_title(value: int) -> String:
	var frame: Dictionary = data.frames[value]
	var text := "%d · %s" % [value,str(frame.label)]
	var action: Variant = frame.get("action")
	if action is Dictionary and action.has("compact"):
		return "%d. %s %s" % [int(action.get("turn",value))+1,"백" if action.get("actor")=="W" else "흑",str(action.compact)]
	if action is Dictionary:
		var destination: Variant = action.get("target") if action.get("target")!=null else action.get("to")
		var origin := _square(action.get("from"))
		if not origin.is_empty(): text += " · "+origin+" → "+_square(destination)
	return text

func report_context() -> String:
	return "리플레이: %s\n수순: %s\n시야: %s\n기대 동작: \n실제 동작: " % [str(data.get("id","")),_frame_title(index),{"all":"전체","W":"백","B":"흑"}[vision]]

func toggle() -> void:
	playing = not playing
	if playing:
		if index==data.frames.size()-1: index=0
		timer.start()
	else: timer.stop()
	show_frame()

func show_frame() -> void:
	var frame: Dictionary = data.frames[index]
	app.board.fx.clear()
	app.pending_fx = {}
	app.view = frame.view.duplicate(true)
	app.view["fx"] = null
	app.feed_signature = ""
	app.result_signature = ""
	app._render()
	var has_vision: bool = frame.has("perspectives")
	if not has_vision: vision = "all"
	for i in range(vision_buttons.size()):
		vision_buttons[i].set_pressed_no_signal(vision==["all","W","B"][i])
		vision_buttons[i].disabled = i>0 and not has_vision
		vision_buttons[i].tooltip_text = "이전 기보에는 당시 시야가 저장되어 있지 않습니다." if not has_vision else ""
	var board_view: Dictionary = app.view.duplicate(true)
	if vision!="all":
		var perspective: Dictionary = frame.perspectives[vision]
		for key in ["grid","scanTiles","exposed","yourColor"]: board_view[key] = perspective.get(key)
	app.board.fog_alpha.clear()
	app.board.set_view(board_view,app.spectating.flipped)
	_transport_layout()
	# Keep the final position inspectable; result is shown in the title.
	app.result_panel.hide()
	app.spectating.presence_row.hide()
	app.ui_shell.set_audience_visible(false)
	app.state_label.text = "리플레이 · "+str(frame.label)
	if app.view.get("phase")=="over":
		app.state_label.text += " · "+("무승부" if app.view.get("winner")=="draw" else ("백 승리" if app.view.get("winner")=="W" else "흑 승리"))
	app.status_label.text = "저장된 기보 재생"
	app.coach_label.text = "보드 시야 전환 · 자동 재생 1.5초 간격" if has_vision else "이전 기보: 전체 시야만 제공됩니다."
	counter.text = "%d / %d · %s" % [index,data.frames.size()-1,str(frame.label)]
	frame_picker.select(index)
	previous_event.disabled = _event_index(-1)<0
	next_event.disabled = _event_index(1)<0
	previous_button.disabled = index==0
	next_button.disabled = index==data.frames.size()-1
	play_button.text = "일시 정지" if playing else "자동 재생"

func close() -> void:
	if not active: return
	timer.stop()
	playing = false
	active = false
	bar.hide()
	vision_bar.hide()
	app.spectating.presence_row.show()
	app.ui_shell.set_audience_visible(true)
	app.seat = return_seat
	app.view = return_view
	app.feed_signature = ""
	app.result_signature = ""
	app._layout()
	if app.room.is_empty(): app._return_home()
	else:
		app.board.set_view(app.view,app.seat=="B")
		app._render()
