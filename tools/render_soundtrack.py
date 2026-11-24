#!/usr/bin/env python3
"""Vector Velocity — 'Through the Neon', an original adaptive racing score.
Render three exactly aligned 64-bar stereo loops. No external samples.
Requires NumPy and FFmpeg with libvorbis. Run from any directory.
"""
from pathlib import Path
import subprocess
import tempfile
import wave
import numpy as np

SR = 32000
BPM = 160
BEAT = 60 / BPM
BARS = 64
N = round(BARS * 4 * BEAT * SR)
TAU = 2 * np.pi
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audio" / "generated"
rng = np.random.default_rng(42813)
stems = [np.zeros((N, 2), dtype=np.float32) for _ in range(3)]

def time(seconds):
    return np.arange(round(seconds * SR), dtype=np.float64) / SR

def hz(note):
    return 440 * 2 ** ((note - 69) / 12)

def env(t, attack, release, duration):
    return np.minimum(t / max(attack, .0001), 1) * np.clip((duration - t) / max(release, .0001), 0, 1)

def put(layer, position, signal, gain=1, pan=0):
    # Equal-power stereo; wrap the effect tails across the loop boundary.
    start = round(position * BEAT * SR) % N
    mono = np.asarray(signal, dtype=np.float32) * gain
    stereo = mono[:, None] * np.array([np.sqrt((1-pan)*.5), np.sqrt((1+pan)*.5)], dtype=np.float32)
    count = min(len(mono), N-start)
    layer[start:start+count] += stereo[:count]
    if count < len(mono):
        layer[:len(mono)-count] += stereo[count:]

def delay(layer, pos, sig, gain, pan):
    put(layer, pos, sig, gain, pan)
    put(layer, pos + .75, sig, gain*.22, -pan)
    put(layer, pos + 1.5, sig, gain*.095, pan)

def kick():
    t = time(.29)
    phase = TAU*(48*t + 58*.027*(1-np.exp(-t/.027)))
    return (np.sin(phase)*np.exp(-t*13)+.12*np.sin(TAU*1300*t)*np.exp(-t*105))*env(t,.0015,.035,.29)

def snare():
    t = time(.23)
    noise = rng.normal(0,1,len(t))
    bright = np.r_[0., np.diff(noise)]
    return (.25*bright*np.exp(-t*21)+.42*np.sin(TAU*(174*t+40*.018*(1-np.exp(-t/.018))))*np.exp(-t*31))*env(t,.001,.045,.23)

def hat(open_hat=False):
    dur = .20 if open_hat else .06
    t = time(dur)
    noise = rng.normal(0,1,len(t))
    high = np.r_[0., np.diff(noise)]
    metal = sum(np.sin(TAU*f*t) for f in (3651, 5327, 7049))/3
    return (.36*high+.14*metal)*np.exp(-t*(15 if open_hat else 58))*env(t,.001,.018,dur)

def bass(note, beats, bright=False):
    dur = beats*BEAT
    t = time(dur)
    p = TAU*hz(note)*t
    sub = .76*np.sin(p)+.13*np.sin(2*p)
    growl = .26*np.sin(2*p+.6*np.sin(TAU*2.1*t))+.10*np.sin(3*p)+.05*np.sin(5*p)
    return (sub + growl*(1 if bright else .35))*env(t,.009,.04,dur)

def pad(note, beats, detune):
    dur = beats*BEAT
    t = time(dur)
    f = hz(note)
    p = TAU*f*t
    return (.57*np.sin(p)+.18*np.sin(p*detune)+.11*np.sin(2*p)+.06*np.sin(3*p)) * env(t,.22,.35,dur)*(0.82+.18*np.sin(TAU*.55*t))

def pluck(note, beats, lead=False):
    dur = beats*BEAT
    t = time(dur)
    p = TAU*hz(note)*t
    if lead:
        vibrato = .095*np.sin(TAU*5.2*t)*np.minimum(t/.12,1)
        sig = .62*np.sin(p+vibrato)+.17*np.sin(2*p)+.09*np.sin(3*p)+.06*np.sin(p*1.003)
        e = env(t,.018,.08,dur)*(.78+.22*np.exp(-t*4))
    else:
        sig = .65*np.sin(p)+.22*np.sin(2*p)*np.exp(-t*8)+.08*np.sin(3*p)*np.exp(-t*16)
        e = env(t,.005,.05,dur)*np.exp(-t*4)
    return sig*e

# D minor. Eight-bar phrase, a contrasting bridge, and an extended reprise.
# Explicit voicings avoid the rigid transposed single-note loop of the old music.
chords = [
    (38,[62,65,69,76]), (34,[58,62,65,69]), (41,[60,65,69,72]), (36,[60,64,67,74]),
    (38,[62,65,69,72]), (34,[58,62,65,72]), (43,[62,67,70,74]), (45,[61,64,69,76]),
]
bridge = [(34,[58,62,65,69]),(36,[60,64,67,74]),(38,[62,65,69,76]),(38,[62,65,69,72]),
          (43,[62,67,70,74]),(41,[60,65,69,72]),(36,[60,64,67,74]),(45,[61,64,69,76])]
motifs = [
    [(0,81,.75),(1,77,.5),(1.75,79,.5),(2.5,81,1.0)],
    [(0,77,1.1),(1.5,74,.5),(2.25,72,.5),(3,74,.75)],
    [(0,76,.5),(0.75,77,.5),(1.5,81,.75),(2.75,79,1)],
    [(0,79,1),(1.5,76,.5),(2.5,74,1.0)],
    [(0,81,.75),(1,84,.5),(1.75,82,.5),(2.5,81,1.0)],
    [(0,77,.75),(1,79,.5),(1.75,77,.5),(2.5,74,1.0)],
    [(0,79,.75),(1,82,.5),(1.75,81,.5),(2.5,79,1.0)],
    [(0,76,.75),(1,73,.5),(1.75,76,.5),(2.5,81,1.0)],
]
for bar in range(BARS):
    pos = bar*4
    part = bar//8
    root, chord = (bridge if part in (2,5) else chords)[bar%8]
    breakdown = part in (2,5)
    full = part in (1,3,4,6,7)
    # Foundation: fast broken-beat rhythm, substantial low end, chord-aware bass.
    kicks = [0, 2.5] if breakdown else ([0, 1.75, 2.5, 3.5] if bar%4==3 else [0, 2.5, 3.25] if bar%2 else [0, 2.5])
    for j in kicks:
        put(stems[0], pos+j, kick(), .40 if j in (0,2.5) else .24)
    for j in (1,3):
        put(stems[0], pos+j, snare(), .39 if not breakdown else .25, .04)
    for j in range(8):
        if breakdown and j%2:
            continue
        put(stems[0], pos+j*.5, hat(j%4==2), .052 if j%2 else .031, -.37 if j%2 else .32)
    bassline = [(0,.72,root),(1, .40,root),(1.75,.55,root+12),(2.5,.7,root),(3.35,.45,root+7)]
    if breakdown:
        bassline = [(0,1.7,root),(2.5,1.0,root)]
    if bar%8==7:
        bassline[-1]=(3.35,.45,37)
    for j,dur,note in bassline:
        put(stems[0],pos+j,bass(note,dur,full),.24)
    # Chords and a syncopated, stereo arpeggio.
    for v,note in enumerate(chord):
        put(stems[1],pos,pad(note,4.0,1.0025 if v%2 else .9975),.10,[-.68,-.25,.27,.67][v])
    order = [0,2,1,3,2,1,3,2] if not breakdown else [0,1,2,3]
    for j,k in enumerate(order):
        note = chord[k]+(12 if j%4==3 else 0)
        delay(stems[1],pos+j*(4/len(order))+.10,pluck(note,.43 if not breakdown else .75),.13, -.44 if j%2 else .44)
    # High-speed layer: independent hook, breakbeat ghost hits, and bright octave pulse.
    for j in (0.75, 2.0, 3.75):
        put(stems[2],pos+j,hat(j==3.75),.05,.56 if j==2.0 else -.56)
    if full:
        for j in (1.75,3.75) if bar%4==3 else (3.5,):
            put(stems[2],pos+j,snare(),.12,-.2)
        for j,dur,note in motifs[bar%8]:
            if part==6 and bar%2==0:
                note += 12
            delay(stems[2],pos+j,pluck(note,dur,True),.21,.12)
        for j in (0.5,1.5,2.5,3.5):
            put(stems[2],pos+j,bass(root+12,.32,True),.10)
    elif not breakdown:
        for j,k in enumerate((0,2,1,3)):
            delay(stems[2],pos+j,pluck(chord[k]+12,.45),.095,.24)
    if bar%8==7:
        # Short filtered-noise transition. No borrowed samples.
        t=time(.72)
        noise=rng.normal(0,1,len(t))
        high=np.r_[0.,np.diff(noise)]
        put(stems[2],pos+2.05,high*env(t,.50,.05,.72),.037)
        for j in (3.25,3.5,3.75):
            put(stems[2],pos+j,snare(),.09)

# Preserve headroom for all three stems playing together. Shared normalization
# preserves relative arrangement levels; use gentle saturation, no hard clipping.
for j,stem in enumerate(stems):
    stems[j]=np.tanh(stem*1.05)/1.05
peak=float(np.max(np.abs(sum(stems))))
gain=min(1.0,.88/max(peak,1e-6))
OUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name,stem in zip(("foundation","harmony","velocity"),stems):
        wav=Path(tmp)/f"{name}.wav"
        samples=np.asarray(np.clip(stem*gain,-1,1)*32767,dtype="<i2")
        rms=float(np.sqrt(np.mean((stem*gain)**2)))
        assert rms>.008 and np.isfinite(stem).all(), f"Invalid stem: {name}"
        with wave.open(str(wav),"wb") as f:
            f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR);f.writeframes(samples.tobytes())
        target=OUT/f"{name}.ogg"
        subprocess.run(["ffmpeg","-v","error","-y","-i",str(wav),"-c:a","libvorbis","-q:a","4",str(target)],check=True)
        length=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",str(target)]))
        assert abs(length-N/SR)<.03 and target.stat().st_size>10000,(name,length)
        print(f"{name}: {length:.2f}s, {target.stat().st_size:,} bytes, RMS {rms:.3f}")
print(f"Original soundtrack: {BARS} bars at {BPM} BPM; aligned loops, mixed peak {peak*gain:.3f}.")
