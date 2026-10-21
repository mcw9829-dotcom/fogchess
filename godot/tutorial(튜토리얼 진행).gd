extends Control
signal progress_changed(step: int)
signal start_game
const Board = preload("res://board(보드·기물·이동 연출).gd")
var step := 0
var chosen := false
var armed := false
var board: Control
var heading: Label
var hint: Label
var ability: Button
var finish: Button
var layout: BoxContainer
var panel: VBoxContainer
var action_menu: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout = BoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	board = Board.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(board)
	board.tapped.connect(_tap)
	action_menu = preload("res://action_menu(기물 행동 메뉴).gd").new()
	board.add_child(action_menu)
	action_menu.chosen.connect(func(_action):
		armed = true
		action_menu.dismiss()
		_render())
	board.selection_cancelled.connect(func():
		chosen = false
		armed = false
		action_menu.dismiss()
		_render())
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation",16)
	layout.add_child(panel)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size",24)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(heading)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(hint)
	ability = Button.new()
	ability.custom_minimum_size.y = 44
	ability.pressed.connect(func(): armed=true; _render())
	panel.add_child(ability)
	finish = Button.new()
	finish.text = "컴퓨터(쉬움)와 첫 대국"
	finish.custom_minimum_size.y = 44
	finish.pressed.connect(func(): start_game.emit())
	panel.add_child(finish)
	var reset := Button.new()
	reset.text = "처음부터"
	reset.custom_minimum_size.y = 42
	reset.pressed.connect(func(): action_menu.dismiss(false); step=0; chosen=false; armed=false; progress_changed.emit(step); _render())
	panel.add_child(reset)
	var cancel = Button.new()
	cancel.text = "선택 취소"
	cancel.custom_minimum_size.y = 44
	cancel.pressed.connect(func(): chosen=false; armed=false; action_menu.dismiss(); _render())
	panel.add_child(cancel)
	resized.connect(_layout)
	_layout()
	_render()

func _layout() -> void:
	layout.vertical = size.x<700
	panel.custom_minimum_size = Vector2(0,230) if layout.vertical else Vector2(280,0)

func _tap(cell: Vector2i) -> void:
	if step==3: return
	var origin: Vector2i = [Vector2i(6,2),Vector2i(6,4),Vector2i(5,2)][step]
	if cell==origin:
		chosen = not chosen
		armed = false
		_render()
		if chosen: action_menu.open_at(board.center(origin),"none" if step==0 else ("scan" if step==1 else "fire"),[false,step>0,step==0],false)
		else: action_menu.dismiss()
		return
	var correct: bool = chosen and armed and ((step==0 and cell==Vector2i(4,1)) or (step>0 and armed and cell==Vector2i(1,5)))
	if correct:
		board.play_fx({"type":"move" if step==0 else ("scan" if step==1 else "fire"),"cells":[[cell.x,cell.y]]})
		action_menu.dismiss(false)
		step+=1
		chosen=false
		armed=false
		progress_changed.emit(step)
		_render()
	else:
		hint.text += "\n표시된 기물 또는 목표를 눌러보세요."

func _render() -> void:
	var titles := ["1 / 3   부쉬에 들어가 적 발견","2 / 3   스캔으로 왕 찾기","3 / 3   보이는 왕 저격","미션 완료!"]
	var messages := ["나이트 선택 → 이동 아이콘 → 표시된 칸을 누르세요.\n\n부쉬에 들어가면 상하좌우로 이어진 덤불 안의 적이 보입니다. 대각선만 닿은 덤불은 별개입니다.","퀸 선택 → 기물 옆 스캔 아이콘 → 표시된 영역을 누르세요.\n\n퀸은 멀리 있는 2×2를 감시할 수 있습니다.","비숍 선택 → 기물 옆 저격 아이콘 → 발견한 왕을 누르세요.\n\n비숍은 사거리 안의 보이는 적을 저격합니다.","부쉬 시야 공유 → 스캔 → 저격을 배웠습니다.\n\n실제 대국에서도 적 왕을 잡으면 승리합니다. 이제 쉬움 봇과 플레이해보세요."]
	heading.text = titles[step]
	hint.text = messages[step] + "\n\n시간제한 없는 고정 연습판 · 전적 미반영"
	ability.visible = false
	ability.disabled = not chosen
	ability.text = "퀸 스캔" if step==1 else "비숍 저격"
	finish.visible = step==3
	var units := [{"r":6 if step==0 else 4,"c":2 if step==0 else 1,"t":"N","o":"W","id":"N"},{"r":6,"c":4,"t":"Q","o":"W","id":"Q"},{"r":5,"c":2,"t":"B","o":"W","id":"B"},{"r":4,"c":7,"t":"P","o":"B"}]
	if step<3: units.append({"r":1,"c":5,"t":"K","o":"B"})
	var grid: Array = []
	for r in range(12):
		var row: Array = []
		for c in range(12):
			var visible := step>=2 and r in [1,2] and c in [5,6]
			for p in units:
				if p.o=="W" and maxi(absi(r-p.r),absi(c-p.c))<=(3 if p.t=="N" else 1): visible=true
			var bush: bool = r==4 and c>=1 and c<=7
			if bush and step>=1: visible=true
			var piece: Variant = null
			for p in units:
				if visible and p.r==r and p.c==c: piece=p
			row.append({"t":3 if bush else 0,"f":0 if visible else 1,"p":piece})
		grid.append(row)
	board.set_view({"room":"tutorial","grid":grid,"phase":"play","yourColor":"W"},false)
	board.selected = [Vector2i(6,2),Vector2i(6,4),Vector2i(5,2),Vector2i(-1,-1)][step] if chosen else Vector2i(-1,-1)
	board.targets = [[4,1]] if step==0 and chosen and armed else ([[1,5]] if armed else [])
	board.mode = "move" if step==0 else ("scan" if step==1 else "fire")
