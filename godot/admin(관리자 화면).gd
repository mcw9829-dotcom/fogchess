extends VBoxContainer
## Admin credentials live only in this dialog and are sent in an HTTP header.
var app: Control
var key := ""
var show_done := false
var busy := false
var auth_generation := 0
var rows: Array = []
var users: Array = []
var error_label: Label

func _ready() -> void:
	show_done = bool(app.prefs.get_value("settings","admin_show_done",false))
	login()

func login(message: String="") -> void:
	auth_generation += 1
	busy = false
	key = ""
	rows.clear(); users.clear()
	app._clear_form(self)
	app._label(self,"관리자 비밀번호로 로그인하세요.",14)
	var password: LineEdit = app._field(self,"관리자 비밀번호","",true)
	error_label = app._label(self,message,12)
	var submit: Button = app._button(self,"관리자 로그인",func():
		if busy or password.text.is_empty(): return
		var candidate := password.text
		password.text = ""
		submit_login(candidate))
	password.text_submitted.connect(func(_text): submit.pressed.emit())
	password.grab_focus()

func submit_login(candidate: String) -> void:
	var stamp := auth_generation
	busy = true
	var response: Dictionary = await app.api.request("/admin/check",null,PackedStringArray(["X-Admin-Key: "+candidate]))
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy = false
	if not response.get("ok",false): login(error_text(response)); return
	key = candidate
	await refresh()

func error_text(response: Dictionary) -> String:
	if response.get("http_status")==429: return "틀린 시도가 많아 잠겼어요. 10분 뒤 다시 시도하세요."
	if response.get("http_status")==403: return "관리자 비밀번호가 틀렸거나 설정되지 않았어요."
	return str(response.get("msg","요청을 처리하지 못했어요."))

func request(path: String,body: Variant=null) -> Dictionary:
	return await app.api.request(path,body,PackedStringArray(["X-Admin-Key: "+key]))

func refresh() -> void:
	if busy: return
	var stamp := auth_generation
	busy = true
	var feedback: Dictionary = await request("/feedback?all=1&limit=300")
	if not is_instance_valid(self) or stamp!=auth_generation: return
	if feedback.get("http_status",200)!=200 or feedback.get("network_error",false):
		busy=false; login(error_text(feedback)); return
	var members: Dictionary = await request("/admin/users")
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy = false
	if members.get("http_status",200)!=200 or members.get("network_error",false): login(error_text(members)); return
	rows = feedback.get("rows",[])
	users = members.get("rows",[])
	render()

func render() -> void:
	app._clear_form(self)
	var open_count := 0
	for entry in rows:
		if not entry.get("done",false): open_count+=1
	app._label(self,"미처리 %d · 처리됨 %d · 회원 %d" % [open_count,rows.size()-open_count,users.size()],14)
	var actions := HFlowContainer.new()
	add_child(actions)
	var filter := CheckButton.new()
	filter.text = "처리된 것도 보기"
	filter.button_pressed = show_done
	actions.add_child(filter)
	filter.toggled.connect(func(value): show_done=value; app.prefs.set_value("settings","admin_show_done",value); app._save(); render())
	app._button(actions,"새로고침",refresh)
	app._button(actions,"관리자 로그아웃",login)
	error_label = app._label(self,"",12)
	app._label(self,"피드백",18)
	var count := 0
	for entry in rows:
		if entry.get("done",false) and not show_done: continue
		count += 1
		var card: VBoxContainer = app._card(self,"")
		var name := str(entry.get("name") if entry.get("name") else "게스트")
		app._label(card,"#%d · %s · %s · %s" % [int(entry.id),{"bug":"버그","balance":"밸런스","idea":"제안","other":"기타"}.get(entry.category,entry.category),name,date(entry.created)],12)
		var context: Label = app._label(card,"방 %s · %s" % [str(entry.room) if entry.get("room") else "—",str(entry.ua) if entry.get("ua") else "—"],11)
		context.tooltip_text = str(entry.ua) if entry.get("ua") else ""
		app._label(card,str(entry.message),14)
		var row := HFlowContainer.new()
		card.add_child(row)
		app._button(row,"미처리로 되돌리기" if entry.get("done",false) else "처리됨",func(): await mutate("/feedback/done",{"id":entry.id,"done":not bool(entry.get("done",false))}))
		app._button(row,"삭제",func(): confirm_delete(int(entry.id)))
	if count==0: app._label(self,"미처리 피드백이 없어요." if not rows.is_empty() else "아직 피드백이 없어요.",13)
	app._label(self,"회원 · 레이팅",18)
	if users.is_empty(): app._label(self,"회원이 없어요.",13)
	for member in users:
		var card: VBoxContainer = app._card(self,"")
		app._label(card,"%s · %d점 · %s" % [member.name,int(member.rating),app.NAMES.get(member.tier,member.tier)],14)
		app._label(card,"%d승 %d패 %d무 · 가입 %s · 복구 코드 %s" % [int(member.wins),int(member.losses),int(member.draws),date(member.created).left(10),"있음" if member.get("hasRecovery",false) else "없음"],12)

func date(value: Variant) -> String:
	return Time.get_datetime_string_from_unix_time(int(value)+int(Time.get_time_zone_from_system().bias)*60).replace("T"," ").left(16)

func confirm_delete(id: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "피드백 삭제"
	dialog.dialog_text = "#%d 피드백을 삭제할까요? 되돌릴 수 없어요." % id
	get_window().add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free(); await mutate("/feedback/delete",{"id":id}))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func mutate(path: String,body: Dictionary) -> void:
	if busy: return
	var stamp := auth_generation
	busy = true
	var response := await request(path,body)
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy = false
	if response.get("http_status",200) in [403,429]: login(error_text(response)); return
	if not response.get("ok",false): error_label.text=error_text(response); return
	await refresh()
