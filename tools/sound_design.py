"""Original, deterministic WW1-inspired game cues. No third-party recordings.

Layered transients, resonant bodies and restrained reflections are synthesized
at 44.1 kHz. These are stylized sounds, not historical weapon recordings.
Only the Python standard library is needed to rebuild the assets.
"""
import array
import math
import random
import wave
from pathlib import Path

RATE = 44100
TAU = math.tau


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x*x*(3-2*x)


class Cue:
    def __init__(self, name, duration):
        self.name = name
        self.data = [0.0]*round(duration*RATE)
        self.rng = random.Random('fogchess-audio-v2-'+name)

    def add(self, start, samples, gain=1.0):
        offset = round(start*RATE)
        for i, sample in enumerate(samples):
            index = i+offset
            if index >= len(self.data): break
            if index >= 0: self.data[index] += sample*gain

    def tone(self, start, duration, freq, gain, decay, end=None, attack=.002, ratios=((1,1),)):
        phase = 0.0
        def signal():
            nonlocal phase
            for i in range(round(duration*RATE)):
                t = i/RATE
                f = freq if end is None else end+(freq-end)*math.exp(-t/.035)
                phase += TAU*f/RATE
                edge = smooth(t/attack)*smooth((duration-t)/.025)
                yield sum(weight*math.sin(phase*ratio) for ratio,weight in ratios)*gain*math.exp(-t/decay)*edge
        self.add(start, signal())

    def noise(self, start, duration, gain, low, high, decay, attack=.001):
        # Difference of two low-pass filters forms a broad, smooth noise band.
        a = 1-math.exp(-TAU*high/RATE)
        b = 1-math.exp(-TAU*low/RATE)
        fast = slow = 0.0
        def signal():
            nonlocal fast, slow
            for i in range(round(duration*RATE)):
                t = i/RATE
                x = self.rng.uniform(-1,1)
                fast += a*(x-fast)
                slow += b*(x-slow)
                yield (fast-slow)*gain*math.exp(-t/decay)*smooth(t/attack)*smooth((duration-t)/.04)
        self.add(start, signal())

    def horn(self, start, duration, freq, gain=.18, soft=False):
        # Detuned additive brass; progressive attack, breath, non-looping release.
        phase = 0.0
        ratios = [(1,1),(2,.52),(3,.28),(4,.13),(5,.055),(6,.025)]
        if soft: ratios = [(1,1),(2,.28),(3,.09),(4,.025)]
        def signal():
            nonlocal phase
            for i in range(round(duration*RATE)):
                t = i/RATE
                env = smooth(t/.045)*smooth((duration-t)/.24)
                vibrato = .0023*math.sin(TAU*4.4*t)*smooth(t/.35)
                phase += TAU*freq*(1+vibrato+.001*math.sin(TAU*.6*t))/RATE
                brightness = .78+.22*smooth(t/.08)
                tone = sum(w*brightness**(h-1)*math.sin(h*phase) for h,w in ratios)
                tone += .12*math.sin(phase*1.003+.3)
                yield tone*gain*env*(.91+.09*math.exp(-t/.18))
        self.add(start, signal())
        self.noise(start, duration, gain*.09, 400, 2500, duration, attack=.04)

    def drum(self, start, gain=.18, big=False):
        self.tone(start,.75 if big else .4,95 if big else 180,gain,.23 if big else .09,
                  end=48 if big else 105,ratios=((1,1),(1.58,.2)))
        self.noise(start,.25,gain*.8,200,2500,.04)

    def reflections(self, taps):
        dry = self.data[:]
        for delay, gain, cutoff in taps:
            filtered = 0.0
            a = 1-math.exp(-TAU*cutoff/RATE)
            offset = round(delay*RATE)
            for i in range(len(dry)-offset):
                filtered += a*(dry[i]-filtered)
                self.data[i+offset] += filtered*gain

    def save(self, folder, peak=.5):
        # DC blocker and short terminal fade avoid clicks. Leave mixing headroom.
        previous = state = 0.0
        for i,x in enumerate(self.data):
            state = x-previous+.995*state
            previous = x
            self.data[i] = math.tanh(state*1.1)*smooth(i/(RATE*.001))*smooth((len(self.data)-1-i)/(RATE*.075))
        highest = max(abs(x) for x in self.data) or 1
        pcm = array.array('h',(round(x/highest*peak*32767) for x in self.data))
        if __import__('sys').byteorder!='little': pcm.byteswap()
        path = Path(folder)/(self.name+'.wav')
        with wave.open(str(path),'wb') as out:
            out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE)
            out.writeframes(pcm.tobytes())


def confirmation(cue, start=0, strength=1):
    cue.noise(start,.095,.65*strength,650,8500,.018)
    cue.tone(start,.22,210,.45*strength,.045,end=105)
    # Single compact metallic signature instead of a sung melody or long blast.
    cue.tone(start+.022,.43,960,.21*strength,.092,
             ratios=((1,1),(1.47,.36),(2.12,.16)),attack=.002)
    cue.tone(start+.062,.28,1440,.10*strength,.055,attack=.003)


def build_combat_audio(folder):
    Path(folder).mkdir(parents=True,exist_ok=True)
    capture=Cue('capture',.62)
    confirmation(capture)
    capture.reflections([(.043,.13,4200),(.097,.07,2500)])
    capture.save(folder,.58)

    fire=Cue('fire',.98)
    # Original sci-fi precision shot: a compact energy intake, one sharp
    # discharge and a bright metallic decay. No sampled game audio.
    def intake():
        phase=0.0
        for i in range(round(.065*RATE)):
            t=i/RATE
            u=t/.065
            phase+=TAU*(720+1250*u*u)/RATE
            yield math.sin(phase+.55*math.sin(phase*1.51))*.095*math.sin(math.pi*u)**2
    fire.add(0,intake())
    fire.noise(.039,.105,.92,1200,8500,.014,attack=.001)
    fire.noise(.043,.23,.47,180,2900,.041)
    fire.tone(.041,.27,290,.48,.044,end=96,ratios=((1,1),(2,.17)))
    def discharge():
        phase=0.0
        for i in range(round(.39*RATE)):
            t=i/RATE
            freq=730+1700*math.exp(-t/.023)
            phase+=TAU*freq/RATE
            fm=(2.0*math.exp(-t/.06)+.12)*math.sin(phase*1.61)
            edge=smooth(t/.0015)*smooth((.39-t)/.03)
            yield math.sin(phase+fm)*.24*math.exp(-t/.066)*edge
    fire.add(.042,discharge())
    fire.tone(.061,.49,1680,.10,.095,ratios=((1,1),(1.41,.26),(2.11,.1)))
    fire.tone(.077,.43,945,.085,.10,ratios=((1,1),(1.73,.18)))
    fire.reflections([(.061,.12,4200),(.119,.065,2900),(.203,.03,1700)])
    fire.save(folder,.5)

    barrage=Cue('barrage',2.15)
    # One cannon discharge. The blast has no repeated firing pulses.
    barrage.noise(0,.19,1.05,250,5400,.033)
    barrage.tone(.002,.85,108,.95,.24,end=43,ratios=((1,1),(2,.22)))
    barrage.noise(.012,1.5,1.65,28,420,.33,attack=.008)
    barrage.noise(.03,.8,.45,160,1400,.18,attack=.008)
    barrage.tone(.015,.9,73,.2,.22,end=55,ratios=((1,1),(1.51,.2)))
    barrage.reflections([(.115,.18,1400),(.197,.13,900),(.311,.09,650),(.473,.055,450)])
    barrage.save(folder,.62)

    kill=Cue('kill',1.10)
    confirmation(kill,strength=1.1)
    kill.drum(.012,.4,True)
    kill.tone(.075,.7,480,.12,.18,ratios=((1,1),(2.01,.32),(2.72,.12)))
    kill.reflections([(.082,.13,2200),(.171,.08,1500)])
    kill.save(folder,.6)

    victory=Cue('victory',3.6)
    for start,freq,length in [(0,196,.55),(.35,293.665,.55),(.73,392,1.45)]:
        victory.horn(start,length,freq,.17)
    victory.horn(.76,1.65,246.942,.09,True)
    victory.horn(.79,1.70,146.832,.08,True)
    victory.drum(0,.13,True); victory.drum(.72,.2,True)
    for t in [.51,.57,.63]: victory.noise(t,.12,.065,700,6500,.025)
    victory.reflections([(.089,.20,3900),(.153,.16,2900),(.239,.12,2200),(.361,.08,1500),(.543,.06,900)])
    victory.save(folder,.42)

    defeat=Cue('defeat',3.4)
    for start,freq,length in [(0,220,.75),(.5,196,.8),(1.02,146.832,1.35)]:
        defeat.horn(start,length,freq,.16,True)
    defeat.horn(.98,1.5,110,.08,True)
    defeat.drum(0,.1,True)
    defeat.reflections([(.097,.18,2600),(.181,.13,2100),(.283,.1,1500),(.439,.07,1000)])
    defeat.save(folder,.38)

    draw=Cue('drawend',3.1)
    draw.horn(0,.95,196,.13,True)
    draw.horn(.66,1.48,146.832,.13,True)
    draw.horn(.69,1.40,220,.065,True)
    draw.tone(.005,.9,588,.035,.25,ratios=((1,1),(2.01,.2)),attack=.012)
    draw.reflections([(.083,.17,3100),(.167,.13,2300),(.271,.10,1600),(.397,.06,1000)])
    draw.save(folder,.36)


def build_interface_audio(folder):
    hover=Cue('ui_hover',.085)
    hover.noise(0,.026,.055,950,3100,.007,attack=.003)
    hover.tone(0,.07,1030,.07,.012,attack=.003,ratios=((1,1),(2,.04)))
    hover.save(folder,.065)
    click=Cue('ui_click',.13)
    click.noise(0,.035,.16,500,4200,.008)
    click.tone(0,.1,700,.12,.014,end=450,ratios=((1,1),(1.7,.15)))
    click.save(folder,.16)
    for enabled in (True,False):
        cue=Cue('ui_on' if enabled else 'ui_off',.22)
        cue.noise(0,.035,.08,800,3200,.007)
        for start,freq in [(0,520 if enabled else 780),(.045,780 if enabled else 520)]:
            cue.tone(start,.14,freq,.13,.028,attack=.002,ratios=((1,1),(2,.08)))
        cue.save(folder,.18)


class LoopCue(Cue):
    def add(self,start,samples,gain=1.0):
        offset=round(start*RATE)
        for i,sample in enumerate(samples): self.data[(i+offset)%len(self.data)]+=sample*gain

    def reflections(self,taps):
        dry=self.data[:]
        for delay,gain,cutoff in taps:
            a=1-math.exp(-TAU*cutoff/RATE)
            state=0.0
            # Warm the filter using the previous loop's tail.
            for x in dry[-RATE:]: state+=a*(x-state)
            offset=round(delay*RATE)
            for i,x in enumerate(dry):
                state+=a*(x-state)
                self.data[(i+offset)%len(dry)]+=state*gain

    def save(self,folder,peak=.22):
        mean=sum(self.data)/len(self.data)
        data=[math.tanh((x-mean)*1.1) for x in self.data]
        gain=peak/max(map(abs,data))
        pcm=array.array('h',(round(x*gain*32767) for x in data))
        if __import__('sys').byteorder!='little': pcm.byteswap()
        with wave.open(str(Path(folder)/(self.name+'.wav')),'wb') as out:
            out.setnchannels(1);out.setsampwidth(2);out.setframerate(RATE);out.writeframes(pcm.tobytes())


def build_lobby_music(folder):
    # 32 seconds / eight 4-beat bars at 60 BPM. Circular composition and
    # reflections preserve release tails across the loop boundary.
    music=LoopCue('lobby',32)
    chords=[(146.832,174.614,220),(116.541,146.832,174.614),
            (130.813,174.614,220),(130.813,164.814,195.998)]
    melody=[293.665,349.228,440,349.228,293.665,261.626,233.082,293.665,
            349.228,440,391.995,349.228,329.628,293.665,261.626,220]
    for bar,chord in enumerate(chords):
        start=bar*8
        for i,freq in enumerate(chord):
            # Slow soft ensemble bed, quieter than the felt-key melody.
            music.horn(start+i*.045,8.8,freq,.018,True)
        for beat in [0,3,4,7]:
            freq=chord[(beat//3)%3]*2
            music.tone(start+beat,2.8,freq,.035,.65,attack=.012,
                       ratios=((1,1),(2,.20),(3,.045)))
    for i,freq in enumerate(melody):
        music.tone(i*2+.5,3.6,freq,.055,.85,attack=.014,
                   ratios=((1,1),(2,.28),(3,.065),(4,.015)))
        music.tone(i*2+.503,3.4,freq*1.001,.018,.9,attack=.017)
    music.reflections([(.131,.22,2600),(.227,.18,2100),(.373,.13,1500),(.613,.09,1000)])
    music.save(folder,.22)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parents[1]/'godot/sounds')
    folder=parser.parse_args().out
    build_combat_audio(folder)
    build_interface_audio(folder)
    build_lobby_music(folder)
