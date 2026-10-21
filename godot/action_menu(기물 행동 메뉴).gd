extends Control
signal chosen(action: String)
signal previewed(action: String)
const Icon = preload("res://action_icon(행동 아이콘·호버).gd")
var buttons: Array[Button] = []
var motion: Tween
var opened := false
var origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for index in range(3):
		var button := Icon.new()
		add_child(button)
		buttons.append(button)
		button.pressed.connect(func(): chosen.emit(button.kind))
		button.mouse_entered.connect(func(): if opened: previewed.emit(button.kind))
		button.mouse_exited.connect(func(): if opened: previewed.emit(""))
		button.focus_entered.connect(func(): if opened: previewed.emit(button.kind))
		button.focus_exited.connect(func(): if opened: previewed.emit(""))
	hide()

func open_at(point: Vector2, ability: String, available: Array, light: bool, animate: bool=true) -> void:
	if is_instance_valid(motion): motion.kill()
	origin = point-Vector2(23,23)
	opened = true
	show()
	var direction := 1.0 if point.y<104 else -1.0
	var offsets := [Vector2(-44,37*direction),Vector2(0,76*direction),Vector2(44,37*direction)]
	var center_x := clampf(point.x,76,size.x-76)
	var actions := ["attack",ability,"move"]
	var labels := {"attack":"공격","move":"이동","scan":"스캔","fire":"저격","barrage":"돌파","none":"능력 없음"}
	motion = create_tween().set_parallel(true)
	for index in range(3):
		var button = buttons[index]
		button.kind = actions[index]
		button.caption = labels.get(button.kind,"능력")
		button.light = light
		button.disabled = not available[index]
		button.tooltip_text = button.caption if available[index] else button.caption+" · 사용 가능한 대상/능력이 없습니다"
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_ALL if available[index] else Control.FOCUS_NONE
		var target: Vector2 = Vector2(center_x,point.y)+offsets[index]-Vector2(23,23)
		target = target.clamp(Vector2.ZERO,size-Vector2(46,46))
		button.position = origin if animate else target
		button.scale = Vector2.ONE*.18 if animate else Vector2.ONE
		button.modulate.a = 0.0 if animate else 1.0
		button.queue_redraw()
		motion.tween_property(button,"position",target,.28 if animate else 0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		motion.tween_property(button,"scale",Vector2.ONE,.28 if animate else 0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		motion.tween_property(button,"modulate:a",1.0,.16 if animate else 0)

func dismiss(animate: bool=true) -> void:
	if not opened: return
	opened = false
	if is_instance_valid(motion): motion.kill()
	motion = create_tween().set_parallel(true)
	for button in buttons:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
		button.release_focus()
		motion.tween_property(button,"position",origin,.16 if animate else 0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		motion.tween_property(button,"scale",Vector2.ONE*.18,.16 if animate else 0)
		motion.tween_property(button,"modulate:a",0.0,.12 if animate else 0)
	motion.chain().tween_callback(hide)
