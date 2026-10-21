extends Node
## One HTTPRequest per operation; no request body or credential logging.
var base_url := "http://127.0.0.1:7556"

func request(path: String, body: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var method := HTTPClient.METHOD_GET if body == null else HTTPClient.METHOD_POST
	var payload := "" if body == null else JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(extra_headers)
	var error := http.request(base_url + path, headers, method, payload)
	if error != OK:
		http.queue_free()
		return {"ok":false, "network_error":true, "msg":"요청을 시작하지 못했습니다 (%s)." % error}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok":false, "network_error":true, "msg":"서버에 연결할 수 없습니다. 개발 서버 실행 여부를 확인하세요."}
	var parsed: Variant = JSON.parse_string(result[3].get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok":false, "network_error":true, "msg":"서버 응답 형식이 올바르지 않습니다."}
	if result[1] < 200 or result[1] >= 300:
		parsed["http_status"] = int(result[1])
		parsed["ok"] = false
		if not parsed.get("msg"):
			parsed["msg"] = "서버 오류 (%s)" % result[1]
	return parsed
