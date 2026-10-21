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
	if data.get("ok"): app.me = data.user; app._update_account()
	elif not data.get("network_error"):
		app.session = ""
		app.me = {}
		app._save()
		app._update_account()

func _account() -> void:
	if app.session.is_empty(): app._auth_form(); return
	if app.matching: app._message("먼저 매칭을 취소하세요."); return
	var pair = app._small_window("내 프로필",380,680)
	var box: VBoxContainer = pair[1]
	var card = HBoxContainer.new()
	box.add_child(card)
	var icon = TextureRect.new()
	icon.texture = load("res://pieces/Chess_%slt45.svg" % str(app.me.get("tier","N")).to_lower())
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(52,52)
	card.add_child(icon)
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(info)
	var display_name = app._label(info,str(app.me.get("name","회원")),18)
	app._label(info,"%s · %s" % [int(app.me.get("rating",1000)),app.NAMES.get(app.me.get("tier","N"),"나이트")],13)
	app._label(info,"%s승 %s패 %s무" % [int(app.me.get("wins",0)),int(app.me.get("losses",0)),int(app.me.get("draws",0))],12)
	app._label(box,"티어 사다리 · 레이팅 구간",12)
	var ladder = HBoxContainer.new()
	box.add_child(ladder)
	var tiers = [[500,"P"],[1000,"N"],[1200,"R"],[1500,"B"],[1700,"Q"],[1900,"K"]]
	var current = 0
	for i in range(tiers.size()):
		if app.me.get("tier")==tiers[i][1]: current = i
	for i in range(tiers.size()):
		var step = VBoxContainer.new()
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ladder.add_child(step)
		var piece = TextureRect.new()
		piece.texture = load("res://pieces/Chess_%slt45.svg" % str(tiers[i][1]).to_lower())
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		piece.custom_minimum_size = Vector2(24,24)
		step.add_child(piece)
		var label = app._label(step,app.NAMES[tiers[i][1]],10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label = app._label(step,"~999" if i==0 else ("1900+" if i==5 else "%s~\n%s" % [tiers[i][0],int(tiers[i+1][0])-1]),9)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i==current: app._label(step,"현재",10).add_theme_color_override("font_color",Color("e6c96a"))
		elif i==current+1: app._label(step,"다음",10)
		elif i<current: step.modulate.a = .5
	var bar = ProgressBar.new()
	bar.show_percentage = false
	var track = StyleBoxFlat.new()
	track.bg_color = Color(0,0,0,.3)
	track.set_corner_radius_all(3)
	var fill = track.duplicate()
	fill.bg_color = Color("c69a5e")
	bar.add_theme_stylebox_override("background",track)
	bar.add_theme_stylebox_override("fill",fill)
	bar.custom_minimum_size.y = 6
	bar.value = 100 if current==5 else clampf((float(app.me.get("rating",1000))-tiers[current][0])/(tiers[current+1][0]-tiers[current][0])*100,0,100)
	box.add_child(bar)
	app._label(box,"최고 티어" if current==5 else "다음 티어 %s(%s)까지 %s점" % [app.NAMES[tiers[current+1][1]],tiers[current+1][0],int(tiers[current+1][0])-int(app.me.get("rating",1000))],11)
	var history = VBoxContainer.new()
	box.add_child(history)
	app._profile_history(history)
	if app.me.get("weakPw",false): app._label(box,"지금 비밀번호는 옛 규칙(숫자 4자리)이에요. 새 규칙으로 바꿔주세요.",12)
	var actions = HFlowContainer.new()
	box.add_child(actions)
	var forms = VBoxContainer.new()
	box.add_child(forms)
	var status = app._label(box,"",12)
	for section in ["name","pw","recov"]:
		app._button(actions,{"name":"닉네임 변경","pw":"비밀번호 변경","recov":"복구 코드 재발급" if app.me.get("hasRecovery",false) else "복구 코드 발급"}[section],func(): app._profile_form(forms,section,status,display_name))
	app._button(box,"로그아웃",func():
		var data: Dictionary = await app.api.request("/logout",{"session":app.session})
		if data.get("ok"):
			app.session = ""
			app.me = {}
			app._save()
			app._update_account()
			if is_instance_valid(pair[0]): pair[0].queue_free()
		elif is_instance_valid(status): status.text = str(data.get("msg","실패했습니다.")))
	if app.me.get("weakPw",false): app._profile_form(forms,"pw",status,display_name)

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
	if signup: app._password_checks(box,password)
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

func _profile_form(parent: Node,section: String,status: Label,display_name: Label) -> void:
	app._clear_form(parent)
	status.text = ""
	var fields: Dictionary = {}
	if section=="name":
		fields.name = app._field(parent,"새 닉네임 (2~12자 · 한글/영문/숫자/_)",str(app.me.get("name","")))
		fields.name.max_length = 12
	elif section=="pw":
		fields.old = app._field(parent,"현재 비밀번호","",true)
		fields.new = app._field(parent,"새 비밀번호 (8자 이상 · 영문+숫자+특수문자)","",true)
		app._password_checks(parent,fields.new)
		fields.confirm = app._field(parent,"새 비밀번호 확인","",true)
	else:
		app._label(parent,"복구 코드는 비밀번호를 잊었을 때 계정을 되찾는 1회용 열쇠예요. 새로 발급하면 이전 코드는 무효가 돼요.",12)
		fields.pw = app._field(parent,"현재 비밀번호 (본인 확인)","",true)
	var error = app._label(parent,"",12)
	error.set_meta("form_error",true)
	var row = HBoxContainer.new()
	parent.add_child(row)
	app._button(row,"취소",func(): app._clear_form(parent))
	var submit = app._button(row,{"name":"저장","pw":"변경","recov":"발급"}[section],func(): pass)
	submit.pressed.connect(func():
		error.text = ""
		var values = {"session":app.session}
		for key in fields: values[key] = fields[key].text
		if section=="name":
			values.name = str(values.name).strip_edges()
			if not app._matches("^[A-Za-z0-9가-힣_]{2,12}$",values.name): error.text = "닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다."; return
			if values.name==app.me.name: app._clear_form(parent); return
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
			display_name.text = str(app.me.name)
			app._update_account()
			status.text = "닉네임을 바꿨어요: "+str(app.me.name)
		elif section=="pw":
			app.me["weakPw"] = false
			status.text = "비밀번호를 바꿨어요. 다른 기기의 로그인은 풀렸어요."
		else:
			app.me["hasRecovery"] = true
			app._recovery(str(data.recovery),"새 복구 코드예요. 이전 코드는 무효가 됐어요.",true)
		app._clear_form(parent))
	for field in fields.values(): field.text_submitted.connect(func(_value): if not submit.disabled: submit.pressed.emit())
	fields.values()[0].grab_focus()

func _profile_history(parent: Node) -> void:
	var title = app._label(parent,"최근 전적 · 불러오는 중…",12)
	var data: Dictionary = await app.api.request("/me/history",{"session":app.session})
	if not is_instance_valid(parent): return
	if not data.get("ok"): title.text = "전적을 불러오지 못했어요."; return
	var rows: Array = data.get("rows",[])
	if rows.is_empty(): title.text = "최근 20판\n아직 기록이 없어요. 첫 판을 두어 보세요!"; return
	var wins = 0
	var losses = 0
	var draws = 0
	var total = 0
	var rated = 0
	for entry in rows:
		if entry.result=="win": wins += 1
		elif entry.result=="loss": losses += 1
		else: draws += 1
		if entry.get("rated",false): total += int(entry.get("delta",0)); rated += 1
	title.text = "최근 %d판 · %d승 %d패%s%s" % [rows.size(),wins,losses," %d무" % draws if draws else ""," · 레이팅 %+d" % total if rated else ""]
	var chart = preload("res://rating_chart(레이팅 그래프).gd").new()
	var chronological = rows.duplicate()
	chronological.reverse()
	for entry in chronological:
		if entry.get("rated",false) and entry.get("rating_after")!=null: chart.values.append(float(entry.rating_after))
	if chart.values.size()>=2: parent.add_child(chart)
	else: chart.free()
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = mini(200,rows.size()*56)
	parent.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in rows:
		var reason: String = {"king":"왕 처치","resign":"기권","disconnect":"접속 끊김","timeout":"미행동","draw":"턴 한도"}.get(entry.get("reason",""),"")
		if entry.result=="win" and entry.get("reason") in ["resign","disconnect","timeout"]: reason = "상대 "+reason
		var date = Time.get_datetime_dict_from_unix_time(int(entry.get("created",0))+int(Time.get_time_zone_from_system().bias)*60)
		var text = "%s · %s · %s%s    %s\n%s · %02d-%02d %02d:%02d" % [{"win":"승","loss":"패","draw":"무"}.get(entry.result,"무"),{"match":"랭크","bot":"컴퓨터","lobby":"친구"}.get(entry.get("kind",""),"대국"),entry.get("opp_name","상대")," (%s)" % entry.opp_rating if entry.get("opp_rating")!=null else "","%+d" % int(entry.get("delta",0)) if entry.get("rated",false) else "비레이팅",reason,date.month,date.day,date.hour,date.minute]
		app._label(list,text,11)
