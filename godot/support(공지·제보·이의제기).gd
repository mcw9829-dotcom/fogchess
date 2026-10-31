extends RefCounted
## Player-facing operations. A support token is scoped to support, never gameplay.
var app
var token = ""
var window: Window
var box: VBoxContainer
var busy = false
const LABELS = {"warn":"경고","chat":"채팅 제한","match":"대국 제한","account":"계정 정지","new":"접수","review":"검토 중","waiting":"보류","accepted":"이의 수용","rejected":"이의 기각","done":"처리 완료","planned":"수정 예정"}
func _init(context) -> void:
	app=context

func create(title: String) -> void:
	var pair = app._small_window(title,640,710)
	window=pair[0]; box=pair[1]
	window.tree_exiting.connect(func(): token="")

func announcements() -> void:
	create("공지 · 점검 안내")
	var pending = app._label(box,"불러오는 중…")
	var data = await app.api.request("/announcements")
	if not is_instance_valid(window): return
	pending.queue_free()
	if not data.get("ok",false): app._label(box,str(data.get("msg","공지를 불러오지 못했습니다."))); return
	if data.get("maintenance",{}).get("paused",false):
		var state = app._card(box,"신규 대국 일시 중단")
		app._label(state,str(data.maintenance.reason))
		app._label(state,"진행 중 대국과 재접속은 이용할 수 있습니다.",12)
	if data.rows.is_empty(): app._label(box,"현재 게시된 공지가 없습니다.")
	for notice in data.rows:
		var card = app._card(box,str(notice.title))
		app._label(card,str(notice.body))

func show_support() -> void:
	create("제재 안내 · 이의제기")
	token=app.session
	if token.is_empty(): login()
	else: await load_mine()

func login() -> void:
	app._label(box,"계정이 정지된 경우에도 본인 인증 후 이의제기를 보낼 수 있습니다.")
	var name = app._field(box,"닉네임")
	var pw = app._field(box,"비밀번호","",true)
	var error = app._label(box,"",13)
	var submit = app._button(box,"본인 확인",func():
		if busy: return
		busy=true
		var candidate=pw.text
		pw.text=""
		var result = await app.api.request("/support/login",{"name":name.text,"pw":candidate})
		if not is_instance_valid(window): return
		busy=false
		if not result.get("ok",false): error.text=str(result.get("msg","인증에 실패했습니다.")); return
		token=str(result.session)
		await load_mine(),"primary")
	pw.text_submitted.connect(func(_v): submit.pressed.emit())

func load_mine() -> void:
	var data = await app.api.request("/support/mine",{"session":token})
	if not is_instance_valid(window): return
	if not data.get("ok",false): app._label(box,str(data.get("msg","안내를 불러오지 못했습니다."))); login(); return
	# Retain the standard window title and close button.
	for child in box.get_children():
		if child!=box.get_child(0): box.remove_child(child); child.queue_free()
	if data.sanctions.is_empty(): app._label(box,"제재 이력이 없습니다.")
	for s in data.sanctions:
		var card = app._card(box,"#%d · %s" % [int(s.id),LABELS.get(s.kind,s.kind)])
		app._label(card,str(s.reason))
		var ended = s.revoked_at!=null or float(s.until_at)<=Time.get_unix_time_from_system()
		app._label(card,"기록" if s.kind=="warn" else ("종료됨" if ended else "적용 중 · "+Time.get_datetime_string_from_unix_time(int(s.until_at))+" UTC"),12)
		if s.revoked_reason!=null: app._label(card,"해제 사유: "+str(s.revoked_reason),12)
		var message = TextEdit.new()
		message.placeholder_text="이의제기 내용 · 3~1000자"
		message.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
		message.custom_minimum_size.y=90
		card.add_child(message)
		var status = app._label(card,"",12)
		app._button(card,"이의제기 보내기",func(): send({"kind":"appeal","sanctionId":int(s.id),"message":message.text},status))
	var tickets = app._card(box,"내 접수 내역")
	if data.tickets.is_empty(): app._label(tickets,"접수한 신고·이의제기가 없습니다.")
	for t in data.tickets: app._label(tickets,"#%d · %s\n%s" % [int(t.id),LABELS.get(t.state,t.state),t.message],13)

func send(payload: Dictionary,status: Label) -> void:
	if busy: return
	if str(payload.get("message","")).strip_edges().length()<3 or str(payload.message).length()>1000:
		status.text="내용을 3~1000자로 입력해 주세요."; return
	busy=true; status.text="접수 중…"
	payload.session=token
	var data = await app.api.request("/support/submit",payload)
	if not is_instance_valid(window): return
	busy=false
	status.text="접수 완료 · #%d" % int(data.id) if data.get("ok",false) else str(data.get("msg","접수하지 못했습니다."))
	if data.get("ok",false) and payload.kind=="appeal": await load_mine()

func report(id: String,frame: int) -> void:
	create("종료 대국 신고")
	token=app.session
	if token.is_empty(): app._label(box,"참여한 회원 계정으로 로그인한 뒤 신고해 주세요."); return
	var data = await app.api.request("/support/context",{"session":token,"replayId":id})
	if not is_instance_valid(window): return
	if not data.get("ok",false): app._label(box,str(data.get("msg","신고할 수 없는 대국입니다."))); return
	app._label(box,"기보 %s · 수순 %d" % [id,frame],12)
	var targets = OptionButton.new()
	targets.add_item("대국 자체 · 특정 회원 없음")
	targets.set_item_metadata(0,null)
	for target in data.targets:
		targets.add_item(str(target.name)); targets.set_item_metadata(targets.item_count-1,int(target.id))
	box.add_child(targets)
	var category = OptionButton.new()
	for name in ["비매너","채팅","규칙 악용","부정행위 의심","기타"]: category.add_item(name)
	box.add_child(category)
	var message = TextEdit.new()
	message.placeholder_text="이 장면에서 어떤 일이 있었나요? · 3~1000자"
	message.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	message.custom_minimum_size.y=180
	box.add_child(message)
	var status = app._label(box,"",12)
	var submit = app._button(box,"신고 접수",func():
		await send({"kind":"report","replayId":id,"frame":frame,"targetUserId":targets.get_item_metadata(targets.selected),"category":["conduct","chat","rules","cheat","other"][category.selected],"message":message.text},status),"primary")

