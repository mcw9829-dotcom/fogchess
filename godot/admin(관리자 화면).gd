extends VBoxContainer
## Auth is memory-only; all mutations are authorized and audited by the server.
var app: Control
var key = ""
var busy = false
var auth_generation = 0
var tab = "overview"
var offset = 0
var query = ""
var selected = ""
var rows: Array = []
var users: Array = []
var response: Dictionary = {}
var error_label: Label
var content: VBoxContainer
var details: VBoxContainer
var balance_kind = "match"
var balance_band = "all"
var balance_days = "7"
var ticket_kind = ""
var notice_draft = false
var last_message = ""
var screens
const TABS = [["overview","운영 현황"],["users","유저 · 제재"],["tickets","신고 · 피드백"],["games","대국 · 정산"],["notices","공지 · 점검"],["balance","밸런스 분석"],["audit","작업 기록"]]
const NAMES = {"warn":"경고","chat":"채팅 제한","match":"랭크 대국","account":"계정 정지","new":"접수","review":"검토 중","planned":"수정 예정","waiting":"보류","done":"처리 완료","accepted":"이의 수용","rejected":"이의 기각","low":"낮음","normal":"보통","high":"높음","bug":"버그","balance":"밸런스","idea":"제안","other":"기타","report":"신고","feedback":"피드백","appeal":"이의제기","conduct":"비매너","rules":"규칙 악용","cheat":"부정행위 의심","update":"업데이트","maintenance":"점검","operations":"운영","clear":"확인 완료","corrected":"정정 완료","bot":"컴퓨터 대국","lobby":"친구 대국","solo":"연습","sanction":"제재 등록","revoke":"제재 해제","ticket":"제보 처리","ticket-delete":"제보 숨김","notice":"공지 변경","adjust":"레이팅 정정","retry":"정산 재시도","error":"오류 확인"}

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	screens = preload("res://admin_pages(관리자 상세 기능).gd").new(self)
	login()

func caption(value: Variant) -> String:
	return str(NAMES.get(str(value),value))

func date(value: Variant) -> String:
	if value==null or float(value)<=0: return "—"
	return Time.get_datetime_string_from_unix_time(int(value)+int(Time.get_time_zone_from_system().bias)*60).replace("T"," ").left(16)

func label(parent: Node,text: String,points: int=14) -> Label:
	return app._label(parent,text,points)

func button(parent: Node,text: String,callback: Callable,role: String="secondary") -> Button:
	var b = app._button(parent,text,func(): if not busy: callback.call(),role)
	b.disabled = busy
	return b

func flow(parent: Node) -> HFlowContainer:
	var f = HFlowContainer.new()
	parent.add_child(f)
	return f

func card(parent: Node,title: String="") -> VBoxContainer:
	var c = app._card(parent,"")
	c.add_theme_constant_override("separation",10)
	if not title.is_empty(): label(c,title,18)
	return c

func choose(parent: Node,title: String,values: Array,current: String) -> OptionButton:
	if not title.is_empty(): label(parent,title,12)
	var field = OptionButton.new()
	field.custom_minimum_size.y = 42
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.clip_text = true
	for value in values:
		field.add_item(caption(value))
		field.set_item_metadata(field.item_count-1,value)
		if str(value)==current: field.select(field.item_count-1)
	parent.add_child(field)
	return field

func choice(field: OptionButton) -> String:
	return str(field.get_item_metadata(field.selected))

func memo(parent: Node,title: String,value: String="",limit: int=1000) -> TextEdit:
	label(parent,title,12)
	var edit = TextEdit.new()
	edit.text = value
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size.y = 110
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	edit.text_changed.connect(func(): if edit.text.length()>limit: edit.text=edit.text.left(limit))
	return edit

func login(message: String="") -> void:
	auth_generation += 1
	busy = false; key = ""
	rows.clear(); users.clear(); response.clear()
	app._clear_form(self)
	var box = card(self,"운영 데스크")
	label(box,"관리자 키로 인증해 주세요. 닫으면 인증 정보가 사라집니다.")
	var entry = HBoxContainer.new()
	entry.add_theme_constant_override("separation",8)
	box.add_child(entry)
	var password = app._field(entry,"관리자 키","",true)
	password.name = "AdminKeyInput"
	password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	var reveal = button(entry,"보기",func(): pass)
	reveal.name = "AdminKeyReveal"
	reveal.toggle_mode = true
	reveal.accessibility_name = "입력한 관리자 키 표시"
	reveal.toggled.connect(func(visible):
		password.secret = not visible
		reveal.text = "숨기기" if visible else "보기"
		password.grab_focus())
	error_label = label(box,message,13)
	var submit = button(box,"관리자 로그인",func():
		if busy or password.text.is_empty(): return
		var candidate = password.text
		password.text = ""
		submit_login(candidate),"primary")
	password.text_submitted.connect(func(_value): submit.pressed.emit())
	password.grab_focus()

func submit_login(candidate: String) -> void:
	var stamp = auth_generation
	busy = true
	error_label.text = "인증 중…"
	var data = await app.api.request("/admin/check",null,PackedStringArray(["X-Admin-Key: "+candidate]))
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy = false
	if not data.get("ok",false): login(error_text(data)); return
	key = candidate
	await refresh()

func error_text(data: Dictionary) -> String:
	if data.get("error")=="forbidden" or int(data.get("http_status",0))==403:
		return "관리자 키가 일치하지 않습니다. 대소문자·한/영 입력을 확인해 주세요."
	if data.get("error")=="locked":
		return str(data.get("msg","인증 시도가 많아 잠시 잠겼습니다. 잠시 후 다시 시도해 주세요."))
	if data.get("network_error",false):
		return "서버에 연결하지 못했습니다. 연결을 확인한 뒤 다시 시도해 주세요."
	return str(data.get("msg","요청을 처리하지 못했습니다. 연결을 확인해 주세요."))

func request(path: String,body: Variant=null) -> Dictionary:
	return await app.api.request(path,body,PackedStringArray(["X-Admin-Key: "+key,"X-Admin-Session: "+app.session]))

func switch_tab(value: String) -> void:
	if busy: return
	tab=value; offset=0; selected=""; query=""; notice_draft=false
	await refresh()

func refresh() -> void:
	if busy or key.is_empty(): return
	var stamp = auth_generation
	busy = true
	if is_instance_valid(error_label): error_label.text="불러오는 중…"
	var route = "/admin/ops/"+tab+"?offset="+str(offset)+"&q="+query.uri_encode()
	if tab=="tickets": route += "&kind="+ticket_kind
	if tab=="balance": route += "&kind="+balance_kind+"&band="+balance_band+"&days="+balance_days
	var data = await request(route)
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy = false
	if data.get("http_status")==403: login(error_text(data)); return
	if not data.get("ok",false): error_label.text=error_text(data); return
	response=data; rows=data.get("rows",[])
	if tab=="users": users=rows
	render()

func render() -> void:
	app._clear_form(self)
	var top = HBoxContainer.new()
	add_child(top)
	label(top,"운영 데스크",24)
	button(top,"새로고침",refresh)
	button(top,"로그아웃",login,"tertiary")
	var nav = flow(self)
	for item in TABS:
		var value: String = item[0]
		var b = button(nav,item[1],func(): switch_tab(value),"primary" if value==tab else "tertiary")
		b.name = "AdminTab_"+value
	error_label = label(self,last_message if not last_message.is_empty() else "서버 연결됨 · 조회 "+date(Time.get_unix_time_from_system()),12)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",14)
	scroll.add_child(content)
	if tab=="overview": screens.overview()
	elif tab=="balance": screens.balance()
	else: listing()

func listing() -> void:
	var controls = HBoxContainer.new()
	content.add_child(controls)
	if tab in ["users","tickets"]:
		var search = app._field(controls,"닉네임 · ID" if tab=="users" else "제보 내용 · 작성자 · ID",query)
		button(controls,"검색",func(): query=search.text.strip_edges(); offset=0; selected=""; refresh())
		search.text_submitted.connect(func(_v): query=search.text.strip_edges(); offset=0; selected=""; refresh())
	if tab=="tickets":
		var filter = choose(controls,"",["전체","feedback","report","appeal"],"전체" if ticket_kind.is_empty() else ticket_kind)
		filter.item_selected.connect(func(_i): ticket_kind=choice(filter) if choice(filter)!="전체" else ""; offset=0; selected=""; refresh())
	if tab=="notices": button(controls,"새 공지",func(): notice_draft=true; render(),"primary")
	var total = int(response.get("total",rows.size()))
	label(content,"%d개 · %d–%d 표시" % [total,offset+1 if total>0 else 0,mini(offset+rows.size(),total)],12)
	var columns = BoxContainer.new()
	columns.vertical=get_window().size.x<760
	columns.add_theme_constant_override("separation",18)
	content.add_child(columns)
	var listbox = VBoxContainer.new()
	listbox.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	listbox.size_flags_stretch_ratio=0.9
	columns.add_child(listbox)
	details = VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio=1.5
	columns.add_child(details)
	if rows.is_empty(): label(listbox,"표시할 항목이 없습니다.")
	var picked: Dictionary = {}
	for row in rows:
		if selected.is_empty(): selected=str(row.id)
		var b = button(listbox,row_title(row),func(): selected=str(row.id); notice_draft=false; render(),"primary" if str(row.id)==selected else "secondary")
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size",13)
		b.custom_minimum_size.y=66
		if str(row.id)==selected: picked=row
	var pages = flow(listbox)
	var limit = 50 if tab=="games" else 100
	if offset>0: button(pages,"이전",func(): offset=maxi(0,offset-limit); selected=""; refresh())
	if offset+rows.size()<total: button(pages,"다음",func(): offset+=limit; selected=""; refresh())
	if tab=="notices" and (notice_draft or rows.is_empty()): screens.notice_form({})
	elif not picked.is_empty():
		match tab:
			"users": load_detail("user?id="+str(int(picked.id)),"user")
			"tickets": screens.ticket_form(picked)
			"games": load_detail("game?id="+str(picked.id),"game")
			"notices": screens.notice_form(picked)
			"audit": screens.audit_detail(picked)
	if tab=="games" and not response.get("legacy",[]).is_empty():
		var old = card(content,"이전 저장 기보 · 최근 30건")
		label(old,"관리 기록 수집 이전 기보는 읽기만 지원합니다.",12)
		for row in response.legacy:
			button(old,"방 %s · %s ↔ %s · 리플레이" % [row.get("room",""),row.get("names",{}).get("W","백"),row.get("names",{}).get("B","흑")],func(): open_replay(str(row.id)))

func row_title(row: Dictionary) -> String:
	match tab:
		"users": return "%s  ·  #%d\n%d점 · %d승 %d패 · 제한 %d건" % [row.name,int(row.id),int(row.rating),int(row.wins),int(row.losses),row.get("restrictions",[]).size()]
		"tickets": return "#%d · %s · %s\n%s · %s" % [int(row.id),caption(row.kind),caption(row.state),str(row.get("name","게스트")),str(row.message).left(45)]
		"games": return "방 %s · %s ↔ %s\n%s · %s" % [row.room,row.names.get("W","백"),row.names.get("B","흑"),date(row.ended),"정산 대기" if row.pending else caption(row.review)]
		"notices": return "%s · %s\n%s" % ["게시 중" if row.published else "초안",caption(row.kind),row.title]
		"audit": return "#%d · %s\n%s · %s" % [int(row.id),caption(row.action),date(row.created),row.actor]
	return ""

func load_detail(route: String,kind: String) -> void:
	var parent = details
	label(parent,"상세 정보 불러오는 중…")
	var stamp = auth_generation
	var current = selected
	var data = await request("/admin/ops/"+route)
	if not is_instance_valid(self) or stamp!=auth_generation or current!=selected or not is_instance_valid(parent) or parent.is_queued_for_deletion(): return
	app._clear_form(parent)
	if not data.get("ok",false): label(parent,error_text(data)); return
	if kind=="user": screens.user_form(data)
	else: screens.game_form(data.game)

func confirm_change(title: String,action: String,payload: Dictionary) -> void:
	if busy: return
	if action!="ticket" and str(payload.get("reason","")).strip_edges().is_empty(): error_label.text="사유를 입력해 주세요."; return
	var popup = preload("res://confirmation_dialog(게임 확인창).gd").new()
	get_window().add_child(popup)
	popup.confirmed.connect(func(): popup.queue_free(); mutate("/admin/ops/"+action,payload))
	popup.canceled.connect(popup.queue_free)
	popup.build(app,"운영 변경 확인",title+"\n\n사유: "+str(payload.get("reason",payload.get("note","검토 단계 변경"))),"적용")

func mutate(path: String,payload: Dictionary) -> void:
	if busy: return
	var body = payload.duplicate(true)
	if not body.has("requestId"): body.requestId=Crypto.new().generate_random_bytes(16).hex_encode()
	var stamp = auth_generation
	busy=true; error_label.text="저장 중…"
	var result = await request(path,body)
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy=false
	if result.get("http_status")==403: login(error_text(result)); return
	if not result.get("ok",false):
		error_label.text=error_text(result)
		if result.get("network_error",false): button(self,"동일 요청 다시 확인",func(): mutate(path,body))
		return
	last_message="저장 완료 · 작업 기록에 남겼습니다."; notice_draft=false
	await refresh()

func open_replay(id: String,frame: int=0) -> void:
	if busy: return
	var stamp=auth_generation
	busy=true
	var result = await request("/admin/ops/replay?id="+id.uri_encode())
	if not is_instance_valid(self) or stamp!=auth_generation: return
	busy=false
	if not result.get("ok",false): error_label.text=error_text(result); return
	app.replay.open_data(result.replay)
	app.replay.seek(frame)
	key=""; auth_generation+=1
	get_window().hide(); get_window().queue_free()
