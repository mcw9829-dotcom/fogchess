extends RefCounted
## Shared timing from the approved '차분한 깊이' study.
const ENTER := .34
const EXIT := .22
const PAGE := .28
const DISTANCE := 22.0
const SCALE := .985

static func ease(progress: float) -> float:
	# CSS cubic-bezier(.16,1,.3,1), solved on x to preserve the preview curve.
	var x := clampf(progress,0,1)
	if x==0 or x==1: return x
	var lo := 0.0
	var hi := 1.0
	for i in range(14):
		var t := (lo+hi)*.5
		var bx := 3*(1-t)*(1-t)*t*.16+3*(1-t)*t*t*.3+t*t*t
		if bx<x: lo=t
		else: hi=t
	return 1-pow(1-(lo+hi)*.5,3)
