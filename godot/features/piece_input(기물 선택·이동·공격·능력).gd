extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app
var preview_mode := ""

func _init(context: Control) -> void:
	app = context

func _clear_selection() -> void:
	preview_mode = ""
	if is_instance_valid(app.action_menu): app.action_menu.dismiss(app.board.effects)
	app.selection = {}
	app.moves = {}
	app.mode = "move"
	if is_instance_valid(app.board):
		app.board.selected = Vector2i(-1,-1)
		app.board.targets = []
		app.board.ranges = []
		app.board.mode = app.mode
	if is_instance_valid(app.selection_label): app._update_selection_ui()

func _update_selection_ui() -> void:
	var selected: bool = not app.selection.is_empty()
	var shown_mode: String = preview_mode if not preview_mode.is_empty() and app.mode=="choose" else app.mode
	app.cancel_selection_button.visible = selected
	app.selection_label.visible = selected
	app.selection_icon.visible = selected
	app.action_details_button.visible = selected
	if not selected: app.action_details.hide()
	app.action_hint.text = ""
	app.action_details.text = ""
	app.coach_label.text = "보드에서 내 기물 선택"
	if app.view.get("phase")=="setup": app.coach_label.text = "내 진영에 배치한 뒤 준비 완료"
	elif app.view.get("phase")=="over": app.coach_label.text = "대국 종료 · 결과 화면을 확인하세요"
	elif app.view.get("turn")!=app.view.get("yourColor"): app.coach_label.text = "상대가 생각 중입니다"
	if selected:
		var cell: Vector2i = app.selection.cell
		app.selection_label.text = "%s · %s%d" % [app.NAMES.get(app.selection.t,"기물"),String.chr(97+cell.y),cell.x+1]
		app.selection_icon.texture = app.board.textures.get(str(app.selection.t).to_lower()+("l" if app.selection.o=="W" else "d"))
		app.action_details.text = {"B":"저격: 사거리 5 안의 보이는 적만 공격합니다. 사격 후 내 위치가 노출됩니다.","R":"돌파 사격: 상하좌우 최대 4칸을 관통합니다. 숲에 막히며 아군도 맞습니다. 빈 방향에도 턴을 사용합니다.","Q":"스캔: 선택 칸을 시작으로 2×2를 감시합니다. 적이 없어도 턴을 사용하며 퀸 위치는 노출되지 않습니다."}.get(app.selection.t,"이동·포획은 표시된 칸에서 가능합니다. 안개 속 이동은 숨은 적에게 가로막힐 수 있습니다.")
		app.coach_label.text = {"choose":"어떤 행동을 할까요?","move":"이동할 칸을 선택하세요","attack":"표시된 적을 선택하세요","fire":"저격할 적을 선택하세요","barrage":"사격 방향을 선택하세요","scan":"스캔 지점을 선택하세요"}.get(shown_mode,"내 진영에 배치하세요")
		app.action_hint.text = {"choose":"기물 옆 아이콘을 선택하세요.\n마우스를 올리면 범위를 볼 수 있어요.","move":"1턴 사용 · 안개 속 경로 주의","attack":"1턴 사용 · 포획","fire":"1턴 사용 · 발사 후 위치 노출","barrage":"1턴 사용 · 아군 피격 / 위치 노출","scan":"1턴 사용 · 2×2 감시"}.get(shown_mode,"")
		if shown_mode=="fire" and app.board.targets.is_empty(): app.coach_label.text="저격 표적 없음"; app.action_hint.text="사거리만 확인할 수 있습니다"
		elif shown_mode=="move" and app.view.get("phase")=="play" and app.board.targets.is_empty(): app.coach_label.text="이동 가능한 칸이 없습니다"
		elif shown_mode=="attack" and app.board.targets.is_empty(): app.coach_label.text="포획 가능한 적이 없습니다"
		elif shown_mode=="choose" and app.moves.get("canFire",false) and app.moves.get("fireCells",[]).is_empty(): app.action_hint.text="저격 표적 없음 · 사거리 확인 가능"
		if int(app.board.tile(cell).get("t",0))==3:
			app.action_hint.text += "\n부쉬 안 · 연결 시야 공유"
			app.action_details.text += "\n부쉬 안에서도 스캔이나 공격 노출로 발각될 수 있습니다."
	if app.view.get("phase")=="setup":
		app.coach_label.text = "내 진영에 배치한 뒤 준비 완료"
		app.action_hint.text = "내 진영 3줄 안에서 배치"
		app.action_details_button.hide()
		app.action_details.hide()

	app.match_ui.render_selection()

func _invalid_target(cell: Vector2i) -> void:
	var reason := "표시된 대상만 선택할 수 있습니다."
	var data: Dictionary = app.board.tile(cell)
	if app.mode=="choose": reason="먼저 기물 주변의 공격 / 능력 / 이동 아이콘을 선택하세요."
	elif app.mode=="fire": reason="사거리 안의 보이는 적만 저격할 수 있습니다."
	elif app.mode=="scan": reason="스캔 가능한 범위 안의 칸을 선택하세요."
	elif app.mode=="barrage": reason="표시된 상하좌우 사격 방향을 선택하세요."
	elif int(data.get("t",0)) in [1,2]: reason="숲·강은 이동할 수 없는 지형입니다."
	elif app.mode=="attack": reason="현재 표시된 포획 가능한 적을 선택하세요."
	elif app.mode=="move": reason="이 기물의 이동 범위·경로를 확인하세요."
	app.coach_label.text = reason
	app.action_hint.text = "턴 소모 없음 · 우클릭으로 취소"

func _set_mode(value: String) -> void:
	app._choose_action(value)

func _move_targets(captures: bool) -> Array:
	var result: Array = []
	for rc in app.moves.get("moves",[]):
		var piece: Variant = app.board.tile(Vector2i(int(rc[0]),int(rc[1]))).get("p")
		var enemy: bool = piece is Dictionary and piece.get("o")!=app.view.get("yourColor")
		if enemy==captures: result.append(rc)
	return result

func _choose_action(value: String) -> void:
	if app.busy or app.selection.is_empty() or app.view.get("phase")!="play" or app.view.get("turn")!=app.view.get("yourColor"): return
	preview_mode = ""
	app.mode = value
	app.action_menu.dismiss(app.board.effects)
	app.board.mode = app.mode
	app.board.targets = app._move_targets(value=="attack") if value in ["move","attack"] else app.moves.get({"fire":"fireCells","barrage":"barrageCells","scan":"scanCells"}.get(value,""),[])
	app.board.ranges = app.moves.get("fireRange",[]) if app.mode=="fire" else []
	app._update_selection_ui()

func _show_actions(animate: bool=true) -> void:
	preview_mode = ""
	var ability = "none"
	for pair in [["canFire","fire"],["canBarrage","barrage"],["canScan","scan"]]:
		if app.moves.get(pair[0],false): ability = pair[1]
	app.mode = "choose"
	app.board.targets = []
	app.board.ranges = []
	app.action_menu.open_at(app.board.center(app.selection.cell),ability,[not app._move_targets(true).is_empty(),ability!="none",not app._move_targets(false).is_empty()],bool(app.prefs.get_value("settings","light",false)),app.board.effects and animate)
	if app._move_targets(true).is_empty(): app.action_menu.buttons[0].tooltip_text = "공격 불가 · 현재 포획 가능한 보이는 적이 없습니다"
	if app._move_targets(false).is_empty(): app.action_menu.buttons[2].tooltip_text = "이동 불가 · 이동 후보 없음 (경로/아군/지형 확인)"
	if ability=="fire" and app.moves.get("fireCells",[]).is_empty(): app.action_menu.buttons[1].tooltip_text = "저격 표적 없음 · 사거리 미리보기만 가능"

func _select(cell: Vector2i) -> void:
	var p: Variant = app.board.tile(cell).get("p")
	if not p is Dictionary or not p.has("id") or p.o!=app.view.get("yourColor"): return
	app.selection = p.duplicate()
	app.selection["cell"] = cell
	app.board.selected = cell
	app.mode = "move"
	app.board.mode = app.mode
	if app.view.get("phase")=="play":
		app.busy = true
		var stamp = app.generation
		var current_turn: Variant = app.view.get("turnCount")
		var data: Dictionary = await app.api.request("/moves?room=%s&token=%s&pid=%s" % [app.room.uri_encode(),app.token.uri_encode(),str(p.id).uri_encode()])
		app.busy = false
		if stamp!=app.generation or current_turn!=app.view.get("turnCount") or app.selection.get("id")!=p.id: return
		if data.get("network_error"): app._report(data); app._clear_selection(); return
		app.moves = data
		app.board.targets = data.get("moves",[])
		app._show_actions()
	app._update_selection_ui()

func _tap(cell: Vector2i) -> void:
	if app.busy or app.view.is_empty() or app.view.get("phase")=="over" or app.view.get("promote"): return
	if app.seat=="spectator":
		app.spectating.inspect(cell)
		return
	var setup: bool = app.view.get("phase")=="setup"
	if not setup and app.view.get("turn")!=app.view.get("yourColor"): app._message("상대 차례입니다."); return
	if not app.selection.is_empty():
		if cell==app.selection.cell: app._clear_selection(); return
		if setup:
			await app._act({"type":"place","pid":app.selection.id,"r":cell.x,"c":cell.y})
			return
		if app.mode!="choose" and app.board.contains(app.board.targets,cell):
			await app._act({"type":"move" if app.mode=="attack" else app.mode,"pid":app.selection.id,"r":cell.x,"c":cell.y})
			return
	var p: Variant = app.board.tile(cell).get("p")
	if p is Dictionary and p.has("id"): await app._select(cell)
	elif not app.selection.is_empty(): _invalid_target(cell)

func _drag(origin: Vector2i,target: Vector2i) -> void:
	if app.seat=="spectator": return
	if app.busy or app.view.is_empty() or app.view.get("phase")=="over" or app.view.get("promote"): return
	if app.view.get("phase")=="play" and app.view.get("turn")!=app.view.get("yourColor"): return
	app._clear_selection()
	await app._select(origin)
	if not app.selection.is_empty():
		if app.view.get("phase")=="play":
			var piece: Variant = app.board.tile(target).get("p")
			app._choose_action("attack" if piece is Dictionary and piece.get("o")!=app.view.get("yourColor") else "move")
		await app._tap(target)

func _preview_action(value: String) -> void:
	if app.mode!="choose" or app.selection.is_empty() or not app.action_menu.opened: return
	preview_mode = value
	app.board.mode = value if not value.is_empty() else "move"
	app.board.targets = app._move_targets(value=="attack") if value in ["move","attack"] else app.moves.get({"fire":"fireCells","barrage":"barrageCells","scan":"scanCells"}.get(value,""),[])
	app.board.ranges = app.moves.get("fireRange",[]) if value=="fire" else []
	app._update_selection_ui()
	if value=="none":
		app.coach_label.text = "이 기물은 고유 능력이 없습니다"
		app.action_hint.text = "공격 또는 이동을 선택하세요."

func _reposition_actions() -> void:
	if app.selection.is_empty() or app.mode!="choose" or not app.action_menu.opened: return
	_show_actions(false)
	app._update_selection_ui()
