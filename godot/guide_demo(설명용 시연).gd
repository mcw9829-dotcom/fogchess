extends "res://original_demo(원본 시연 재현).gd"
var kind := "P"

func _ready() -> void:
	for entry in scenes().guide:
		if entry.t==kind: spec=entry; break
	custom_minimum_size = Vector2(172,172)
	frames = [{"p":[3,3],"phase":"행마"}]
	for move in spec.get("moves",[]):
		var target := absolute(move)
		frames.append({"p":target,"dot":[target],"phase":"행마"})
		frames.append({"p":[3,3],"phase":"행마"})
	for phase in [spec.get("capture",{}),spec.get("ability",{})]:
		var first := frames.size()
		match phase.get("mode",""):
			"move":
				var enemy := absolute(phase.enemy)
				frames.append({"p":[3,3],"foes":[enemy]})
				frames.append({"p":enemy,"foes":[enemy],"hit":[enemy],"fx":{"type":"capture","cells":[enemy]},"snd":"capture"})
				frames.append({"p":enemy,"foes":[]})
				frames.append({"p":[3,3]})
			"shot":
				var enemies: Array = phase.enemies.map(absolute)
				var path: Array = phase.path.map(absolute)
				var effect := {"type":"barrage" if kind=="R" else "fire","cells":path if kind=="R" else enemies,"from":[3,3]}
				frames.append({"p":[3,3],"foes":enemies})
				frames.append({"p":[3,3],"foes":enemies,"beam":path})
				frames.append({"p":[3,3],"foes":[],"hit":enemies,"exposed":true,"fx":effect,"snd":effect.type})
				frames.append({"p":[3,3]})
			"scan":
				var area: Array = phase.area.map(absolute)
				var hidden := absolute(phase.hidden)
				frames.append({"p":[3,3],"fog":area})
				frames.append({"p":[3,3],"scan":area,"foes":[hidden],"fx":{"type":"scan","cells":area,"extra":[hidden]},"snd":"scan"})
				frames.append({"p":[3,3],"scan":area,"foes":[hidden]})
				frames.append({"p":[3,3]})
		for frame_index in range(first,frames.size()):
			frames[frame_index]["phase"] = "공격" if phase==spec.get("capture",{}) else "능력"
	super._ready()

func absolute(rc: Array) -> Array: return [3+int(rc[0]),3+int(rc[1])]
