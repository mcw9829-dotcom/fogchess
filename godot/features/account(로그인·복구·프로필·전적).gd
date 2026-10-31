extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

func _init(context: Control) -> void:
	app = context

func _update_account() -> void:
	app.account_label.text = "로그인하면 내 순위가 여기에 표시돼요" if app.me.is_empty() else "%s · %d점" % [app.me.name,int(app.me.rating)]
	app._layout()

func _refresh_profile() -> void:
	if app.session.is_empty(): return
	var data: Dictionary = await app.api.request("/me",{"session":app.session})
	if data.get("ok"):
		app.me = data.user
		app.lobby_status.set_active(data.get("activeGame"))
		app._update_account()
	elif not data.get("network_error"):
		app.session = ""
		app.me = {}
		app._save()
		app._update_account()

func _account() -> void:
	if app.session.is_empty(): app._auth_form(); return
	if app.matching: app._message("먼저 매칭을 취소하세요."); return
	preload("res://features/profile_ui.gd").new(app,self).open()

func _delete_form() -> void:
	var pair = app._small_window("계정 삭제",420,490)
	var box: VBoxContainer = pair[1]
	app._label(box,"삭제한 계정은 복구할 수 없습니다",19)
	app._label(box,"계정·레이팅·개인 전적을 삭제하고 모든 기기에서 로그아웃합니다. 진행 중인 대국은 먼저 마쳐 주세요.",14)
	app._label(box,"상대방의 대국 기록·공유 리플레이와 제출한 신고·피드백·운영 기록은 남습니다. 이 기기의 리플레이 목록도 유지됩니다.",14)
	var password = app._field(box,"현재 비밀번호","",true)
	password.max_length = 64
	var agree = CheckBox.new()
	agree.text = "삭제 내용을 확인했습니다"
	agree.custom_minimum_size.y = 48
	box.add_child(agree)
	var status = app._label(box,"",13)
	status.set_meta("form_error",true)
	var remove = app._button(box,"계정 영구 삭제",func(): pass,"danger")
	remove.disabled = true
	var update = func(_value): remove.disabled = not agree.button_pressed or password.text.is_empty()
	password.text_changed.connect(update)
	agree.toggled.connect(update)
	remove.pressed.connect(func():
		if remove.disabled: return
		remove.disabled = true
		agree.disabled = true
		password.editable = false
		var result: Dictionary = await app.api.request("/account/delete",{"session":app.session,"pw":password.text,"confirm":"DELETE"})
		if result.get("ok"):
			app.session = ""
			app.me = {}
			app.matching = false
			app.lobby_status.set_active(null)
			app.lobby_status.set_queue({})
			if not app.room.is_empty(): app._return_home()
			app._save(); app._update_account(); app._load_home_ranks()
			app._message("계정을 삭제했습니다.")
			if is_instance_valid(pair[0]): password.text = ""; pair[0].queue_free()
		elif is_instance_valid(status):
			status.text = str(result.get("msg","삭제하지 못했습니다. 다시 시도해 주세요."))
			agree.disabled = false
			password.editable = true
			password.text = ""
			update.call(false)
			if result.has("activeGame"): app.lobby_status.set_active(result.activeGame))
	app._button(box,"취소",func(): pair[0].queue_free())

func _authenticated(data: Dictionary) -> void:
	app.session = str(data.session)
	app.me = data.user
	app.me["weakPw"] = bool(data.get("weakPw",false))
	app._save()
	app._update_account()
	if data.get("recovery"): app._recovery(str(data.recovery))
	elif app.me.weakPw: app._account()

func _recovery(code: String,subtitle: String="가입 완료! 이 코드는 지금 한 번만 보여요.",back: bool=false) -> void:
	var pair = app._small_window("복구 코드 보관",380,400)
	app._label(pair[1],subtitle,13)
	var field = app._field(pair[1],"",code)
	field.editable = false
	app._label(pair[1],"비밀번호를 잊었을 때 계정을 되찾는 1회용 열쇠예요. 안전한 곳에 보관하세요.",12)
	var status = app._label(pair[1],"",12)
	app._button(pair[1],"코드 복사",func(): DisplayServer.clipboard_set(code); status.text = "복사했어요.")
	app._button(pair[1],"보관했어요",func():
		pair[0].queue_free()
		if back or app.me.get("weakPw",false): app._account())

func _auth_form(signup: bool=false) -> void:
	var pair = app._small_window("계정",380,430)
	var box: VBoxContainer = pair[1]
	var tabs = HBoxContainer.new()
	box.add_child(tabs)
	var login = app._button(tabs,"로그인",func(): pair[0].queue_free(); app._auth_form(false))
	var register = app._button(tabs,"회원가입",func(): pair[0].queue_free(); app._auth_form(true))
	login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	register.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app._tint_button(register if signup else login,Color("c69a5e"),true)
	var name_field = app._field(box,"닉네임 (2~12자 · 한글/영문/숫자/_)")
	name_field.max_length = 12
	var password = app._field(box,"비밀번호 (8자 이상 · 영문+숫자+특수문자)" if signup else "비밀번호","",true)
	password.max_length = 64
	if signup:
		app._password_checks(box,password)
		app._label(box,"게스트 전적·레이팅은 이전되지 않습니다. 이 기기의 리플레이 목록은 유지됩니다.",12)
	var error = app._label(box,"",12)
	error.set_meta("form_error",true)
	error.custom_minimum_size.y = 24
	var submit = app._form_action(box,"회원가입" if signup else "로그인","닉네임과 비밀번호만 있으면 끝 · 레이팅 1000부터 시작" if signup else "닉네임과 비밀번호로 입장","user",signup)
	submit.set_meta("auth_submit",true)
	var authenticate = func():
		if submit.disabled: return
		if name_field.text.strip_edges().is_empty(): error.text = "닉네임을 입력하세요."; name_field.grab_focus(); return
		error.text = ""
		var problem = app._password_problem(password.text) if signup else ("비밀번호를 입력하세요." if password.text.is_empty() else "")
		if not problem.is_empty(): error.text = problem; password.grab_focus(); return
		submit.disabled = true
		var data: Dictionary = await app.api.request("/signup" if signup else "/login",{"name":name_field.text.strip_edges(),"pw":password.text})
		if not is_instance_valid(submit): return
		submit.disabled = false
		if data.get("ok"):
			password.text = ""
			pair[0].hide()
			pair[0].queue_free()
			app._authenticated(data)
			app._load_home_ranks()
		else: error.text = str(data.get("msg","실패했습니다."))
	submit.pressed.connect(authenticate)
	password.text_submitted.connect(func(_value): authenticate.call())
	name_field.text_submitted.connect(func(_value): authenticate.call())
	if not signup: app._button(box,"비밀번호나 닉네임을 잊었나요?",func(): pair[0].queue_free(); app._find_account())
	app._label(box,"비밀번호는 해시로만 저장돼요(서버에 평문 없음).",11)
	name_field.grab_focus()

func _matches(pattern: String,value: String) -> bool:
	var regex = RegEx.new()
	regex.compile(pattern)
	return regex.search(value)!=null

func _password_problem(value: String) -> String:
	if value.length()<8 or value.length()>64: return "비밀번호는 8~64자입니다."
	if app._matches("\\s",value): return "비밀번호에 공백은 쓸 수 없습니다."
	if not app._matches("\\p{L}",value): return "비밀번호에 영문(문자)을 넣어주세요."
	if not app._matches("[0-9]",value): return "비밀번호에 숫자를 넣어주세요."
	if not app._matches("[^\\p{L}\\p{N}\\s]",value): return "비밀번호에 특수문자(!@#$ 등)를 넣어주세요."
	return ""

func _password_checks(parent: Node,field: LineEdit) -> void:
	field.max_length = 64
	var row = HFlowContainer.new()
	parent.add_child(row)
	var labels: Array = []
	for text in ["8자 이상","영문","숫자","특수문자"]: labels.append(app._label(row,text,11))
	var refresh = func(value: String):
		var valid = [value.length()>=8 and value.length()<=64,app._matches("\\p{L}",value),app._matches("[0-9]",value),app._matches("[^\\p{L}\\p{N}\\s]",value)]
		for i in range(4): labels[i].add_theme_color_override("font_color",Color("82bc8d") if valid[i] else Color("9a938a"))
	field.text_changed.connect(refresh)
	refresh.call(field.text)

func _find_account() -> void:
	var pair = app._small_window("비밀번호 · 닉네임 찾기",380,430)
	app._label(pair[1],"가입할 때 받은 복구 코드(FOG-XXXX-XXXX)를 넣으면 새 비밀번호를 정하고 닉네임을 알려드려요. 코드는 1회용이라 새 코드가 다시 발급돼요.",12)
	var code = app._field(pair[1],"복구 코드 (FOG-XXXX-XXXX)")
	var password = app._field(pair[1],"새 비밀번호 (8자 이상 · 영문+숫자+특수문자)","",true)
	app._password_checks(pair[1],password)
	var error = app._label(pair[1],"",12)
	error.set_meta("form_error",true)
	var submit = app._form_action(pair[1],"새 비밀번호로 바꾸고 로그인","닉네임도 알려드려요 · 다른 기기는 로그아웃","user",true)
	submit.pressed.connect(func():
		var normalized = code.text.to_upper().strip_edges()
		var regex = RegEx.new()
		regex.compile("[^A-Z0-9]")
		normalized = regex.sub(normalized,"",true).trim_prefix("FOG")
		if normalized.length()!=8: error.text = "복구 코드(FOG-XXXX-XXXX)를 입력하세요."; code.grab_focus(); return
		error.text = ""
		var problem = app._password_problem(password.text)
		if not problem.is_empty(): error.text = problem; password.grab_focus(); return
		submit.disabled = true
		var data: Dictionary = await app.api.request("/recover/code",{"code":code.text.strip_edges(),"new":password.text})
		if not is_instance_valid(submit): return
		submit.disabled = false
		if data.get("ok"):
			password.text = ""
			pair[0].queue_free()
			app.session = str(data.session)
			app.me = data.user
			app._save()
			app._update_account()
			app._recovery(str(data.recovery),"비밀번호를 바꿨어요. 닉네임은 "+str(app.me.name)+" · 쓴 코드는 무효가 되고 새 코드가 발급됐어요.")
		else: error.text = str(data.get("msg","실패했습니다.")))
	app._button(pair[1],"← 로그인으로",func(): pair[0].queue_free(); app._auth_form())
	password.text_submitted.connect(func(_value): if not submit.disabled: submit.pressed.emit())
	code.grab_focus()

func _close_profile_form(parent: Node) -> void:
	app._clear_form(parent)
	if parent.has_meta("management_actions"):
		var actions: Control = parent.get_meta("management_actions")
		if is_instance_valid(actions): actions.show()
		parent.hide()

func _profile_form(parent: Node,section: String,status: Label,display_name: Label) -> void:
	app._clear_form(parent)
	parent.show()
	status.text = ""
	status.hide()
	parent.set_meta("profile_form_section",section)
	var back: Button = app._button(parent,"← 계정 관리",func(): _close_profile_form(parent),"tertiary")
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.set_meta("profile_action","form_back")
	app._label(parent,{"name":"닉네임 변경","pw":"비밀번호 변경","recov":"복구 코드 발급"}[section],18)
	var fields: Dictionary = {}
	if section=="name":
		app._label(parent,"새 닉네임",14)
		app._label(parent,"2~12자 · 한글, 영문, 숫자, _",13)
		fields.name = app._field(parent,"새 닉네임",str(app.me.get("name","")))
		fields.name.max_length = 12
	elif section=="pw":
		app._label(parent,"현재 비밀번호",14)
		fields.old = app._field(parent,"현재 비밀번호","",true)
		app._label(parent,"새 비밀번호",14)
		fields.new = app._field(parent,"영문·숫자·특수문자 포함","",true)
		app._password_checks(parent,fields.new)
		for label in parent.get_child(parent.get_child_count()-1).get_children():
			if label is Label: label.add_theme_font_size_override("font_size",14)
		app._label(parent,"새 비밀번호 확인",14)
		fields.confirm = app._field(parent,"다시 입력","",true)
	else:
		app._label(parent,"비밀번호를 잊었을 때 계정을 되찾는 1회용 코드입니다. 새로 발급하면 이전 코드는 사용할 수 없습니다.",14)
		app._label(parent,"현재 비밀번호",14)
		fields.pw = app._field(parent,"본인 확인용 비밀번호","",true)
	for key in fields:
		fields[key].set_meta("profile_field",key)
		fields[key].custom_minimum_size.y = 46
		if key!="name": fields[key].max_length = 64
	var error = app._label(parent,"",14)
	error.set_meta("form_error",true)
	error.set_meta("profile_form_error",true)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	var cancel: Button = app._button(row,"취소",func(): _close_profile_form(parent))
	cancel.set_meta("profile_action","form_cancel")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var submit = app._button(row,{"name":"저장","pw":"변경","recov":"코드 발급"}[section],func(): pass,"primary")
	submit.set_meta("profile_action","form_submit")
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(func():
		if submit.disabled: return
		error.text = ""
		var values = {"session":app.session}
		for key in fields: values[key] = fields[key].text
		if section=="name":
			values.name = str(values.name).strip_edges()
			if not app._matches("^[A-Za-z0-9가-힣_]{2,12}$",values.name): error.text = "닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다."; return
			if values.name==app.me.name: _close_profile_form(parent); return
		elif section=="pw":
			var problem = app._password_problem(values.new)
			if not problem.is_empty(): error.text = problem; fields.new.grab_focus(); return
			if values.new!=values.confirm: error.text = "새 비밀번호 확인이 일치하지 않습니다."; fields.confirm.grab_focus(); return
			if values.old==values.new: error.text = "현재 비밀번호와 다르게 정해주세요."; return
			values.erase("confirm")
		elif str(values.pw).is_empty(): error.text = "현재 비밀번호를 입력하세요."; fields.pw.grab_focus(); return
		submit.disabled = true
		var data: Dictionary = await app.api.request({"name":"/account/name","pw":"/account/pw","recov":"/account/recovery"}[section],values)
		if not is_instance_valid(submit): return
		submit.disabled = false
		if not data.get("ok"): error.text = str(data.get("msg","실패했습니다.")); return
		if section=="name":
			var weak: bool = app.me.get("weakPw",false)
			app.me = data.user
			app.me["weakPw"] = weak
			if is_instance_valid(display_name): display_name.text = str(app.me.name)
			app._update_account()
			status.text = "닉네임을 바꿨어요: "+str(app.me.name)
		elif section=="pw":
			app.me["weakPw"] = false
			if parent.has_meta("profile_warning") and is_instance_valid(parent.get_meta("profile_warning")): parent.get_meta("profile_warning").hide()
			status.text = "비밀번호를 바꿨어요. 다른 기기의 로그인은 풀렸어요."
		else:
			app.me["hasRecovery"] = true
			# The recovery screen replaces this profile; its back action opens a fresh one.
			if parent.get_window().get_meta("profile_window",false): parent.get_window().queue_free()
			app._recovery(str(data.recovery),"새 복구 코드예요. 이전 코드는 무효가 됐어요.",true)
			return
		status.show()
		_close_profile_form(parent))
	for field in fields.values(): field.text_submitted.connect(func(_value): if not submit.disabled: submit.pressed.emit())
	fields.values()[0].grab_focus()

func _profile_history(parent: Node) -> void:
	await preload("res://features/profile_ui.gd").new(app,self).load_history(parent,true)
