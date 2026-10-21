"""Windows-only native dialog roundtrip; not an IME keystroke simulation."""
import ctypes
from ctypes import wintypes
from pathlib import Path
import subprocess,time
root=Path(__file__).resolve().parent
user=ctypes.windll.user32
user.SendMessageW.argtypes=[wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM]
user.SendMessageW.restype=ctypes.c_ssize_t
log=root/'godot/tests/native-chat.log'
process=subprocess.Popen([r'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe','--path',str(root/'godot'),'--script','res://tests/native_chat.gd','--log-file',str(log),'--','--smoke'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
callback=ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
dialog=[]
@callback
def find_window(hwnd,_):
    pid=wintypes.DWORD(); user.GetWindowThreadProcessId(hwnd,ctypes.byref(pid))
    if pid.value==process.pid:
        title=ctypes.create_unicode_buffer(256);user.GetWindowTextW(hwnd,title,256)
        if title.value=='Fog Chess · 한글 채팅 입력': dialog.append(hwnd)
    return True
try:
    for _ in range(100):
        user.EnumWindows(find_window,0)
        if dialog:break
        time.sleep(.1)
    assert dialog,'Native test dialog not found'
    fields=[]
    @callback
    def find_edit(hwnd,_):
        name=ctypes.create_unicode_buffer(100);user.GetClassNameW(hwnd,name,100)
        if name.value=='Edit':fields.append(hwnd)
        return True
    user.EnumChildWindows(dialog[0],find_edit,0)
    assert fields,'Native edit control missing'
    time.sleep(1)
    phrase=ctypes.create_unicode_buffer('안녕 세상아')
    user.SendMessageW(fields[0],0x000C,0,ctypes.cast(phrase,ctypes.c_void_p).value)
    user.SendMessageW(dialog[0],0x0111,1,0)
    code=process.wait(timeout=12)
    output=log.read_text(encoding='utf-8');print(output)
    assert code==0 and 'NATIVE_DIALOG_PASS=true' in output
finally:
    if process.poll() is None:process.terminate();process.wait(timeout=5)
