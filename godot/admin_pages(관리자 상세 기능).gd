extends RefCounted
var ui
var app
func _init(controller) -> void:
	ui=controller; app=ui.app

func overview() -> void:
	var data = ui.response
	var metrics = ui.flow(ui.content)
	for item in [["최근 활동 회원",data.get("online",[]).size()],["진행 중 대국",data.get("running",[]).size()],["매칭 대기",data.get("queue",[]).size()],["미처리 제보",data.counts.get("tickets",0)],["정산 대기",data.counts.get("pending",0)]]:
		var tile = ui.card(metrics)
		tile.get_parent().custom_minimum_size.x=155
		ui.label(tile,str(int(item[1])),28)
		ui.label(tile,str(item[0]),13)
	ui.label(ui.content,"최근 활동은 90초 안에 접속 신호가 확인된 로그인 회원입니다. 새로고침 시 갱신됩니다.",12)
	var state = ui.card(ui.content,"신규 대국 "+("일시 중단" if data.maintenance.paused else "정상 운영"))
	if not str(data.maintenance.reason).is_empty(): ui.label(state,str(data.maintenance.reason),13)
	ui.button(state,"공지 · 점검 관리",func(): ui.switch_tab("notices"),"tertiary")
	for group in [["진행 중 대국","running"],["매칭 대기","queue"],["최근 활동 회원","online"]]:
		var box = ui.card(ui.content,group[0])
		var entries = data.get(group[1],[])
		if entries.is_empty(): ui.label(box,"현재 항목이 없습니다.")
		for row in entries:
			if group[1]=="running": ui.label(box,"방 %s   %s ↔ %s   · %s" % [row.room,row.names.get("W","백"),row.names.get("B","흑"),"배치 중" if row.phase=="setup" else "대국 중"])
			elif group[1]=="queue": ui.label(box,"%s · %d점 · %d초 대기" % [row.name,int(row.rating),int(row.waited)])
			else: ui.label(box,"%s · %d점 · %s" % [row.name,int(row.rating),ui.date(row.seen)])
	var errors = ui.card(ui.content,"서버 오류 · 최근 50건")
	if data.get("errors",[]).is_empty(): ui.label(errors,"수집된 오류가 없습니다.")
	for row in data.get("errors",[]):
		ui.label(errors,"%s · %s · %s · %s" % [ui.date(row.created),row.route,row.kind,"확인됨" if row.resolved else "미확인"],13)
		if not row.resolved:
			var reason = app._field(errors,"확인 내용")
			ui.button(errors,"확인 완료",func(): ui.confirm_change("오류 확인","error",{"id":int(row.id),"reason":reason.text}))
	ui.label(ui.content,"백업 상태: 별도 백업 시스템과 연결되지 않았습니다.",12)

func user_form(data: Dictionary) -> void:
	var user = data.user
	var box = ui.card(ui.details,"%s · #%d" % [user.name,int(user.id)])
	ui.label(box,"%d점 · %d승 %d패 %d무\n가입 %s" % [int(user.rating),int(user.wins),int(user.losses),int(user.draws),ui.date(user.created)])
	var kind = ui.choose(box,"조치",["warn","chat","match","account"],"warn")
	kind.set_item_text(2,"대국 제한")
	var days = SpinBox.new()
	days.min_value=1; days.max_value=30; days.value=1; days.suffix="일"
	days.custom_minimum_size.y=42
	box.add_child(days)
	ui.label(box,"경고는 기록과 본인 안내만 남깁니다. 대국 제한은 새 대국만, 계정 정지는 로그인·대국·채팅을 제한합니다.",12)
	var reason = ui.memo(box,"조치 사유 · 대상 회원에게 표시됩니다","",500)
	ui.button(box,"조치 검토",func(): ui.confirm_change("%s · %s · %d일" % [user.name,kind.get_item_text(kind.selected),0 if ui.choice(kind)=="warn" else int(days.value)],"sanction",{"userId":int(user.id),"kind":ui.choice(kind),"days":int(days.value),"reason":reason.text}),"primary")
	var history = ui.card(ui.details,"제재 기록")
	if data.sanctions.is_empty(): ui.label(history,"제재 이력이 없습니다.")
	for s in data.sanctions:
		var active = s.kind!="warn" and s.revoked_at==null and float(s.until_at)>Time.get_unix_time_from_system()
		ui.label(history,"#%d %s · %s\n%s\n%s → %s" % [int(s.id),"대국 제한" if s.kind=="match" else ui.caption(s.kind),"적용 중" if active else "기록",s.reason,ui.date(s.created),ui.date(s.until_at)],13)
		if active:
			var release = app._field(history,"해제 사유")
			ui.button(history,"제재 해제",func(): ui.confirm_change("%s · 제재 #%d 해제" % [user.name,int(s.id)],"revoke",{"id":int(s.id),"reason":release.text}))
	var games = ui.card(ui.details,"최근 전적 · 20판")
	if data.history.is_empty(): ui.label(games,"전적이 없습니다.")
	for g in data.history: ui.label(games,"%s · %s · %s · %+d점" % [ui.date(g.created),str(g.opp_name),str(g.result),int(g.get("delta",0))],13)

func ticket_form(row: Dictionary) -> void:
	var box = ui.card(ui.details,"#%d · %s" % [int(row.id),ui.caption(row.kind)])
	ui.label(box,"%s · %s" % [str(row.get("name","게스트")),ui.date(row.created)],12)
	ui.label(box,str(row.message),16)
	if row.get("target_name")!=null: ui.label(box,"대상 회원: "+str(row.target_name))
	if row.get("sanction_id")!=null: ui.label(box,"연결된 제재 #%d" % int(row.sanction_id))
	if row.get("replay_id")!=null:
		ui.label(box,"기보 %s · 수순 %s" % [row.replay_id,str(row.get("frame_index","—"))],12)
		ui.button(box,"증거 리플레이 열기",func(): ui.open_replay(str(row.replay_id),int(row.get("frame_index",0))))
	var categories = ["bug","balance","idea","other"] if row.kind=="feedback" else (["appeal"] if row.kind=="appeal" else ["conduct","chat","rules","cheat","other"])
	var category = ui.choose(box,"분류",categories,str(row.category))
	var state = ui.choose(box,"처리 상태",["new","review","waiting","accepted","rejected"] if row.kind=="appeal" else ["new","review","planned","waiting","done"],str(row.state))
	var priority = ui.choose(box,"우선순위",["low","normal","high"],str(row.priority))
	var note = ui.memo(box,"내부 검토 메모 · 완료 시 필수",str(row.admin_note))
	if row.kind=="appeal": ui.label(box,"이의 수용과 제재 해제는 별도 작업입니다. 필요하면 유저 · 제재에서 해제하세요.",12)
	ui.button(box,"처리 내용 저장",func(): ui.confirm_change("제보 #%d · %s → %s" % [int(row.id),ui.caption(row.state),ui.caption(ui.choice(state))],"ticket",{"id":int(row.id),"revision":int(row.revision),"state":ui.choice(state),"category":ui.choice(category),"priority":ui.choice(priority),"note":note.text}),"primary")
	var hide_reason = app._field(box,"목록에서 숨길 사유")
	ui.button(box,"제보 숨기기",func(): ui.confirm_change("제보 #%d 목록에서 숨김 · 감사 기록은 보존" % int(row.id),"ticket-delete",{"id":int(row.id),"revision":int(row.revision),"reason":hide_reason.text}),"tertiary")

func game_form(g: Dictionary) -> void:
	var box = ui.card(ui.details,"방 "+str(g.room))
	ui.label(box,"%s ↔ %s\n%s · %s" % [g.names.get("W","백"),g.names.get("B","흑"),ui.caption(g.kind),ui.date(g.ended)],16)
	ui.label(box,"종료: %s · 승자: %s" % [str(g.reason),"백" if g.winner=="W" else ("흑" if g.winner=="B" else "무승부")])
	ui.label(box,"대국 ID · "+str(g.id),11)
	if g.get("replay_id")!=null: ui.button(box,"종료 리플레이 열기",func(): ui.open_replay(str(g.replay_id)),"primary")
	var reason = ui.memo(box,"검토 · 정산 변경 사유","",500)
	if g.pending:
		ui.label(box,"정산 대기 · 저장된 원래 결과로 재처리합니다.")
		ui.button(box,"정산 재시도",func(): ui.confirm_change("방 %s · 정산 재시도" % g.room,"retry",{"id":g.id,"revision":int(g.revision),"reason":reason.text}),"primary")
	else:
		ui.button(box,"검토 완료",func(): ui.confirm_change("방 %s · 검토 완료" % g.room,"review",{"id":g.id,"revision":int(g.revision),"reason":reason.text}))
		if not g.result.is_empty():
			ui.label(box,"레이팅 정정 · 이 대국의 증감을 변경",16)
			ui.label(box,"이후 레이팅 기록과 현재 점수도 차이만큼 이동합니다. 승패 기록은 그대로입니다.",12)
			var fields = {}
			for side in g.result:
				ui.label(box,"%s · 기존 %+d점 → 정정 증감" % [g.names.get(side,side),int(g.result[side].delta)],13)
				var edit = SpinBox.new()
				edit.min_value=-1000; edit.max_value=1000; edit.value=int(g.result[side].delta)
				box.add_child(edit); fields[side]=edit
			ui.button(box,"정정 내용 검토",func():
				var deltas = {}
				var summary = "방 "+str(g.room)+" · 레이팅 정정"
				for side in fields:
					deltas[side]=int(fields[side].value)
					summary += "\n%s: %+d → %+d" % [g.names.get(side,side),int(g.result[side].delta),deltas[side]]
				ui.confirm_change(summary,"adjust",{"id":g.id,"revision":int(g.revision),"deltas":deltas,"reason":reason.text}))
	var evidence = ui.card(ui.details,"종료 대국 기록")
	ui.label(evidence,"기보 %d개 · 채팅 %d개" % [g.notation.size(),g.chat.size()],13)
	for m in g.chat: ui.label(evidence,str(m.get("name",m.get("color","")))+"  "+str(m.get("text",m.get("message",""))),13)
	if g.chat.is_empty(): ui.label(evidence,"저장된 채팅이 없습니다.",13)

func notice_form(row: Dictionary) -> void:
	var box = ui.card(ui.details,"새 공지" if row.is_empty() else "공지 편집")
	var title = app._field(box,"제목 · 60자 이내",str(row.get("title","")))
	title.max_length=60
	var kind = ui.choose(box,"분류",["update","maintenance","operations"],str(row.get("kind","operations")))
	var body = ui.memo(box,"내용 · 2,000자 이내",str(row.get("body","")),2000)
	var publish = CheckButton.new()
	publish.text="로비에 게시"; publish.button_pressed=bool(row.get("published",false))
	box.add_child(publish)
	var reason = app._field(box,"변경 사유")
	ui.button(box,"공지 저장",func():
		var data = {"title":title.text,"body":body.text,"kind":ui.choice(kind),"published":publish.button_pressed,"reason":reason.text}
		if not row.is_empty(): data.merge({"id":int(row.id),"revision":int(row.revision)})
		ui.confirm_change("공지 · "+title.text+"\n"+("로비에 게시" if publish.button_pressed else "초안으로 저장"),"notice",data),"primary")
	load_maintenance(ui.details)

func load_maintenance(parent: Node) -> void:
	var stamp = ui.auth_generation
	var data = await ui.request("/admin/ops/overview")
	if not is_instance_valid(ui) or stamp!=ui.auth_generation or not is_instance_valid(parent) or parent.is_queued_for_deletion(): return
	if not data.get("ok",false): ui.label(parent,ui.error_text(data)); return
	var state = data.maintenance
	var box = ui.card(parent,"신규 대국 · "+("일시 중단 중" if state.paused else "운영 중"))
	ui.label(box,"랭크 매칭·새 방·컴퓨터 대국·재대국에 적용됩니다. 진행 중인 대국과 본인 방 재접속은 유지합니다.",13)
	if not str(state.reason).is_empty(): ui.label(box,str(state.reason),13)
	var reason = app._field(box,"운영 사유 · 플레이어에게 표시")
	ui.button(box,"신규 대국 재개" if state.paused else "신규 대국 일시 중단",func(): ui.confirm_change("신규 대국 "+("재개" if state.paused else "일시 중단"),"maintenance",{"paused":not state.paused,"expectedPaused":state.paused,"reason":reason.text}))

func audit_detail(row: Dictionary) -> void:
	var box = ui.card(ui.details,ui.caption(row.action)+" · #"+str(int(row.id)))
	ui.label(box,"%s\n%s · 대상 %s" % [row.actor,ui.date(row.created),str(row.target)],13)
	ui.label(box,"사유 · "+str(row.reason),16)
	ui.label(box,"변경 전",13); ui.label(box,JSON.stringify(row.before,"  "),12)
	ui.label(box,"변경 후",13); ui.label(box,JSON.stringify(row.after,"  "),12)
	ui.label(box,"작업 기록은 읽기 전용입니다.",12)

func balance() -> void:
	var filters = ui.flow(ui.content)
	var kind = ui.choose(filters,"대국 종류",["match","bot","lobby"],ui.balance_kind)
	var band = ui.choose(filters,"평균 시작 레이팅",["all","1000","1400","1800"],ui.balance_band)
	for i in range(4): band.set_item_text(i,["전체","1000–1399","1400–1799","1800 이상"][i])
	var days = ui.choose(filters,"기간",["7","30","90"],ui.balance_days)
	for i in range(3): days.set_item_text(i,["최근 7일","최근 30일","최근 90일"][i])
	ui.button(filters,"조회",func(): ui.balance_kind=ui.choice(kind); ui.balance_band=ui.choice(band); ui.balance_days=ui.choice(days); ui.refresh())
	var count = int(ui.response.get("games",0))
	ui.label(ui.content,"종료 대국 %d판" % count,24)
	ui.label(ui.content,"관리 데이터 수집 시작: "+ui.date(ui.response.get("since"))+" · 실제 기록만 집계합니다.",12)
	if count==0: ui.label(ui.content,"이 조건에 맞는 표본이 없습니다. 새로 종료된 대국부터 누적됩니다.",16)
	var out = ui.response.get("outcomes",{})
	for v in [["백 승리",int(out.get("W",0))],["흑 승리",int(out.get("B",0))],["무승부",count-int(out.get("W",0))-int(out.get("B",0))]]:
		var box = ui.card(ui.content)
		ui.label(box,"%s · %d판 · %.1f%%" % [v[0],v[1],float(v[1])*100/maxi(1,count)])
		var bar = ProgressBar.new()
		bar.value=float(v[1])*100/maxi(1,count); bar.show_percentage=false; bar.custom_minimum_size.y=10
		box.add_child(bar)
	var abilities = ui.card(ui.content,"기물 능력 사용")
	for item in [["fire","비숍 저격"],["barrage","룩 돌파사격"],["scan","퀸 스캔"]]:
		var uses = int(ui.response.get("uses",{}).get(item[0],0))
		var measured = int(ui.response.get("measuredUses",{}).get(item[0],0))
		var hits = int(ui.response.get("captureUses",{}).get(item[0],0))
		ui.label(abilities,"%s · %d회" % [item[1],uses],16)
		if item[0]!="scan": ui.label(abilities,"포획 발생률 %s · 측정 %d회" % [("%.1f%%" % (100.0*hits/measured)) if measured>0 else "—",measured],12)
	ui.label(ui.content,"표본이 적을 때 승률만으로 밸런스를 판단하지 마세요. 스캔은 포획률을 계산하지 않습니다.",12)
