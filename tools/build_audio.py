"""Reproducible native PCM port of sound.js (no third-party audio assets)."""
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
    'capture': [(0,180,.12,'sawtooth',.22,90),(0,0,.15,'noise',.25,0)],
    'fire': [(0,90,.5,'sawtooth',.3,40),(0,0,.5,'noise',.5,0)],
    'barrage': [(i*.055,140,.06,'square',.16,0) for i in range(4)]+[(0,0,.35,'noise',.4,0)],
    'kill': [(0,70,.7,'sawtooth',.35,30),(0,0,.7,'noise',.6,0),(.12,520,.3,'square',.2,0)],
    'victory': [(i*.095,f,.2,'square',.16,0) for i,f in enumerate([523,659,784,1047])],
    'defeat': [(i*.130,f,.28,'sawtooth',.16,0) for i,f in enumerate([392,330,262])],
    'drawend': [(0,440,.18,'triangle',.14,0),(.15,392,.24,'triangle',.14,0)],
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

for name, events in EVENTS.items():
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

# 100 seconds is a shared period of 110/164.81/220 Hz and the .05 Hz LFO.
# This preserves pitch without the old 2-second discontinuity. Master fade is runtime.
def ambient():
    x1=x2=y1=y2=0.0
    for i in range(-RATE,100*RATE):
        t=i/RATE
        x=.5*math.sin(math.tau*110*t)+.3*math.sin(math.tau*164.81*t)+.18*oscillator(220*t,'triangle',220/RATE)
        cutoff=520+170*math.sin(math.tau*.05*t)
        w=math.tau*cutoff/RATE
        # WebAudio lowpass Q is specified in dB; Q=5 => 10^(5/20).
        alpha=math.sin(w)/(2*10**(5/20))
        a0=1+alpha
        b0=(1-math.cos(w))*.5/a0
        y=b0*x+2*b0*x1+b0*x2+2*math.cos(w)/a0*y1-(1-alpha)/a0*y2
        x2,x1,y2,y1=x1,x,y1,y
        if i>=0: yield y*.06
save('ambient',ambient())
print('Built 11 original sound cues and 100-second seamless ambient loop.')
