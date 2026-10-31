"""Build original game cues; four legacy cues plus the WW1-inspired redesign."""
import array
import math
import random
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / 'godot' / 'sounds'
OUT.mkdir(parents=True, exist_ok=True)
# delay, frequency, duration, waveform, gain, exponential destination
EVENTS = {
    'move': [(0,320,.08,'triangle',.18,0)],
    'place': [(0,440,.05,'square',.12,0)],
    'yourturn': [(0,880,.12,'sine',.16,0),(.09,1175,.16,'sine',.16,0)],
    'scan': [(0,600,.18,'sine',.13,1500),(.09,950,.14,'sine',.11,1700)]}

def blep(phase, step):
    if phase < step:
        t=phase/step
        return t+t-t*t-1
    if phase > 1-step:
        t=(phase-1)/step
        return t*t+t+t+1
    return 0

def oscillator(phase, kind, step):
    p=phase%1
    if kind=='sine': return math.sin(math.tau*p)
    if kind=='triangle': return 2/math.pi*math.asin(math.sin(math.tau*p))
    if kind=='square': return (1 if p<.5 else -1)+blep(p,step)-blep((p+.5)%1,step)
    # Web Audio's sawtooth Fourier series starts at zero with positive slope.
    p=(p+.5)%1
    return 2*p-1-blep(p,step)

def save(name, samples):
    pcm=array.array('h',(round(max(-1,min(1,s))*32767) for s in samples))
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(pcm.tobytes())

for name in ("move", "place", "yourturn", "scan"):
    events = EVENTS[name]
    samples=[0.0]*math.ceil(max(e[0]+e[2] for e in events)*RATE)
    rng=random.Random(name)
    for delay,freq,duration,kind,gain,dest in events:
        phase=0
        for i in range(round(duration*RATE)):
            t=i/RATE
            frequency=freq*(dest/freq)**(t/duration) if dest else freq
            if kind=='noise': sample=rng.uniform(-1,1)*(1-i/(duration*RATE))**2*gain
            else:
                sample=oscillator(phase,kind,frequency/RATE)*gain*(.001/gain)**(t/duration)
                phase+=frequency/RATE
            samples[round(delay*RATE)+i]+=sample
    save(name,samples)

# Combat remains music-free. Only the lobby has an original looping track.
from sound_design import build_combat_audio, build_interface_audio, build_lobby_music
build_combat_audio(OUT)
build_interface_audio(OUT)
build_lobby_music(OUT)
print('Built 15 sound cues and a 32-second lobby loop. No combat BGM.')
