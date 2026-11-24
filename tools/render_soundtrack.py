#!/usr/bin/env python3
"""Vector Velocity — REDLINE FRACTURE. Original industrial breakcore score.
All instruments and patterns synthesized offline; no borrowed samples.
Requires numpy and ffmpeg/libvorbis.
"""
from pathlib import Path
from functools import lru_cache
import subprocess, tempfile, wave
import numpy as np

SR=44100
BPM=190
BEAT=60/BPM
BARS=80
N=round(BARS*4*BEAT*SR)
TAU=2*np.pi
OUT=Path(__file__).resolve().parents[1]/"audio"/"generated"
rng=np.random.default_rng(76245)
mix=np.zeros((N,2),np.float32)

def time(seconds):
    return np.arange(round(seconds*SR),dtype=np.float64)/SR

def hz(note):
    return 440*2**((note-69)/12)

def envelope(t, attack, release, duration):
    return np.minimum(t/attack,1)*np.clip((duration-t)/release,0,1)

def put(beat,sig,gain=1.,pan=0.):
    start=round(beat*BEAT*SR)%N
    stereo=np.asarray(sig,dtype=np.float32)[:,None]*np.array([np.sqrt((1-pan)*.5),np.sqrt((1+pan)*.5)],np.float32)*gain
    n=min(len(sig),N-start)
    mix[start:start+n]+=stereo[:n]
    if n<len(sig):mix[:len(sig)-n]+=stereo[n:]

@lru_cache(maxsize=8)
def kick(hard=True):
    t=time(.24)
    phase=TAU*(46*t+105*.019*(1-np.exp(-t/.019)))
    body=np.sin(phase)*np.exp(-t*17)
    click=np.sin(TAU*1680*t)*np.exp(-t*120)*.17
    return np.tanh((body+click)*(2.2 if hard else 1.3))*envelope(t,.0015,.035,.24)

def snare(variant=0):
    t=time(.18 if variant==0 else .09)
    noise=rng.normal(0,1,len(t))
    mid=np.convolve(noise,[.14,.22,.28,.22,.14],mode="same")
    body=np.sin(TAU*(182*t+54*.016*(1-np.exp(-t/.016))))*np.exp(-t*34)
    return np.tanh((.95*mid*np.exp(-t*23)+.72*body)*1.9)*envelope(t,.001,.025,t[-1]+1/SR)

def hat(open_hat=False):
    dur=.19 if open_hat else .045
    t=time(dur)
    noise=rng.normal(0,1,len(t))
    high=np.r_[0,np.diff(noise)]
    metallic=sum(np.sin(TAU*f*t) for f in (3521,4933,6811))/3
    return (.25*high+.18*metallic)*np.exp(-t*(18 if open_hat else 72))*envelope(t,.0015,.015,dur)

@lru_cache(maxsize=256)
def guitar(note,beats,voice=0,muted=True):
    dur=beats*BEAT
    t=time(dur)
    freq=hz(note)*(1.003 if voice else .997)
    phase=TAU*freq*t+.04*np.sin(TAU*5.6*t)
    # Band-limited additive strings and cabinet-like rolloff. Layer
    # separately voiced fifths, rather than copying a guitar recording.
    sig=sum(np.sin(phase*k)/(k**.78) for k in range(1,min(17,int(8500/freq))+1))
    amp=(.38+.62*np.exp(-t*15)) if muted else (.72+.28*np.exp(-t*3))
    raw=np.tanh(sig*1.7*amp)
    # Mild smoothing reduces digital fizz after intentional distortion.
    raw=np.convolve(raw,[.12,.24,.28,.24,.12],mode="same")
    return raw*envelope(t,.004,.022 if muted else .055,dur)

@lru_cache(maxsize=160)
def bass(note,beats,acid=False):
    dur=beats*BEAT
    t=time(dur)
    p=TAU*hz(note)*t
    sub=.85*np.sin(p)
    growl=np.tanh((np.sin(2*p+.8*np.sin(TAU*9*t))+.45*np.sin(3*p)+.2*np.sin(5*p))*1.8)
    return (sub+growl*(.55 if acid else .25))*envelope(t,.006,.035,dur)

@lru_cache(maxsize=128)
def lead(note,beats):
    dur=beats*BEAT
    t=time(dur)
    p=TAU*hz(note)*t+.12*np.sin(TAU*6.2*t)
    return np.tanh((np.sin(p)+.35*np.sin(2*p)+.18*np.sin(3*p))*1.35)*envelope(t,.012,.065,dur)

# Ten evolving eight-bar movements: thrash, chopped breaks, odd
# syncopations, halftime industrial section, then a final double-time riff.
roots=[38,38,41,37,38,34,43,36]
alt=[38,41,37,38,34,35,36,37]
riffs=[
 [(0,0,.42),(.5,0,.22),(.75,0,.22),(1,3,.42),(1.5,0,.42),(2,0,.42),(2.5,6,.42),(3,5,.42),(3.5,1,.42)],
 [(0,0,.7),(.75,0,.2),(1,7,.43),(1.5,6,.43),(2,0,.22),(2.25,0,.22),(2.5,3,.7),(3.25,1,.22),(3.5,0,.42)],
 [(0,0,.42),(.5,0,.42),(1,1,.22),(1.25,3,.22),(1.5,5,.42),(2,0,.7),(2.75,6,.22),(3,3,.42),(3.5,1,.42)],
 [(0,0,1.35),(1.5,6,.42),(2,0,1.35),(3.5,1,.42)],
 [(0,0,.22),(.25,0,.22),(.5,0,.22),(.75,1,.22),(1,3,.42),(1.5,0,.42),(2,0,.22),(2.25,0,.22),(2.5,6,.42),(3,5,.22),(3.25,3,.22),(3.5,1,.42)]
]
patterns=[
 ([0,.75,1.5,2.5,3.25],[1,3]),
 ([0,.5,1.75,2,2.75,3.5],[1,2.5,3.25]),
 ([0,.25,.5,1.5,2,2.25,2.5,3.5],[1,3]),
 ([0,1.5,2.75],[2]),
 ([0,.75,1.25,1.75,2.5,3.5,3.75],[.5,1.5,3])
]
hooks=[
 [74,75,81,80,77,73,74,77],
 [74,81,80,77,75,73,68,70],
 [86,85,81,80,77,80,75,73],
 [74,77,80,81,85,80,77,75]
]
for bar in range(BARS):
    beat=bar*4
    part=bar//8
    p=[0,1,2,1,3,4,2,0,4,2][part]
    root=(alt if part in (2,5,6,8) else roots)[bar%8]
    ks,ss=patterns[p]
    for k in ks:put(beat+k,kick(),.50 if k in (0,2) else .36)
    for k in ss:put(beat+k,snare(),.46)
    for k in ([.25,1.75,2.25,3.75] if p in (1,2,4) else [1.75,3.75]):
        put(beat+k,snare(1),.15,(-.25 if k<2 else .25))
    for step in range(16):
        if p==3 and step%2:continue
        put(beat+step*.25,hat(step%8==6),.082 if step%2==0 else .046,(-.45 if step%2 else .45))
    if bar%4==3:
        for k in (3.0,3.25,3.5,3.625,3.75,3.875):
            put(beat+k,snare(1),.13+.035*(k-3))
    for offset,interval,length in riffs[p]:
        note=root+interval
        put(beat+offset,bass(note-12,length,p in (1,2,4)),.29)
        for voice,pan in [(0,-.72),(1,.72)]:
            put(beat+offset,guitar(note,length,voice,p!=3),.22,pan)
            put(beat+offset,guitar(note+7,length,voice,p!=3),.105,pan)
    # Distinct lead phrases enter and leave without an abrupt silent gap.
    if part in (1,2,3,5,6,8,9):
        melody=hooks[(part+bar//4)%4]
        for step in range(4 if p==3 else 8):
            note=melody[(step+bar%4*2)%8]
            offset=step*(1 if p==3 else .5)
            sig=lead(note,.82 if p==3 else .39)
            put(beat+offset,sig,.11,.12)
            put(beat+offset+.75,sig,.027,-.45)
    if bar%8==7:
        t=time(.65)
        sweep=np.convolve(rng.normal(0,1,len(t)),[.1,.2,.4,.2,.1],mode="same")
        put(beat+2.0,sweep*envelope(t,.45,.06,.65),.17)
# Loudness control: intentional instrument distortion, not clipped final audio.
mix=np.tanh(mix*1.15)
peak=float(np.max(np.abs(mix)))
mix*=.86/max(peak,1e-6)
fade=round(.008*SR)
mix[-fade:]+=np.linspace(0,1,fade,dtype=np.float32)[:,None]*(mix[0]-mix[-1])
rms=float(np.sqrt(np.mean(mix**2)))
assert np.isfinite(mix).all() and .02<rms<.55
OUT.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    wav=Path(tmp)/"redline.wav"
    with wave.open(str(wav),"wb") as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
        f.writeframes(np.asarray(np.clip(mix,-1,1)*32767,dtype="<i2").tobytes())
    target=OUT/"soundtrack.ogg"
    subprocess.run(["ffmpeg","-v","error","-y","-i",str(wav),"-c:a","libvorbis","-q:a","5",str(target)],check=True)
    length=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",str(target)]))
    assert abs(length-N/SR)<.03 and target.stat().st_size>10000
    print(f"REDLINE FRACTURE: {BPM} BPM, {length:.2f}s, RMS {rms:.3f}, {target.stat().st_size:,} bytes")
