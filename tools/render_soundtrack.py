#!/usr/bin/env python3
"""Vector Velocity — REDLINE RIOT. Original hard-rock score with adaptive stems.
All instruments and patterns synthesized offline; no borrowed samples.
Requires numpy and ffmpeg/libvorbis.
"""
from pathlib import Path
from functools import lru_cache
import subprocess, tempfile, wave
import numpy as np

SR=44100
BPM=132
BEAT=60/BPM
BARS=48
N=round(BARS*4*BEAT*SR)
TAU=2*np.pi
OUT=Path(__file__).resolve().parents[1]/"audio"/"generated"
rng=np.random.default_rng(76245)
mix=np.zeros((N,2),np.float32)
intensity=np.zeros_like(mix)
active_mix=mix

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
    active_mix[start:start+n]+=stereo[:n]
    if n<len(sig):active_mix[:len(sig)-n]+=stereo[n:]

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
    return (.12*high+.07*metallic)*np.exp(-t*(18 if open_hat else 72))*envelope(t,.0015,.015,dur)

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
    # Simulated cabinet: saturate then attenuate sub and high fizz.
    raw=np.tanh(sig*1.35*amp)
    spectrum=np.fft.rfft(raw)
    freq_bins=np.fft.rfftfreq(len(raw),1/SR)
    response=(freq_bins/(freq_bins+95.0))*(1/(1+(freq_bins/2800.0)**4))
    response*=1+.18*np.exp(-((freq_bins-900)/650)**2)
    raw=np.fft.irfft(spectrum*response,n=len(raw))
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

# REDLINE RIOT: original 132 BPM hard-rock instrumental, not an
# arrangement, sample, or interpolation of any existing song.
# Both stems are identical-length and phase-aligned for adaptive mixing.
roots=[45,45,48,43,41,41,48,43,45,48,43,40,45,45,41,43]
riffs=[
 [(0,0,.70),(.75,0,.22),(1.25,7,.42),(2,0,.43),(2.5,3,.42),(3.25,5,.61)],
 [(0,0,.92),(1.25,12,.42),(2,7,.42),(2.5,5,.42),(3.25,0,.63)],
 [(0,0,.45),(.5,0,.40),(1.25,5,.55),(2,7,.70),(3,3,.85)],
 [(0,0,1.32),(1.5,7,.45),(2.25,5,.65),(3.25,0,.60)]
]
lead_phrases=[
 [(0,72,.62),(.75,76,.40),(1.5,74,.72),(2.5,69,.95)],
 [(0,67,.90),(1.25,72,.62),(2,76,.45),(2.75,74,.90)],
 [(0,77,.72),(1,74,.45),(1.75,72,.72),(3,69,.82)],
 [(0,71,.60),(.75,74,.70),(1.75,76,.82),(3,72,.80)]
]
for bar in range(BARS):
    beat=bar*4
    section=bar//8
    root=roots[(bar+section*4)%len(roots)]
    riff=riffs[(bar+section)%len(riffs)]
    active_mix=mix
    for offset in ([0,1.5,2,3.5] if bar%2==0 else [0,.75,2,2.75]):
        put(beat+offset,kick(),.53)
    for offset in [1,3]:put(beat+offset,snare(),.49)
    for step in range(8):put(beat+step*.5,hat(step==7),.045 if step%2==0 else .025,(-.4 if step%2 else .4))
    for offset,interval,length in riff:
        note=root+interval
        put(beat+offset,bass(note-12,length),.36)
        # Rhythmic power chords with an original syncopated contour.
        for voice,pan in [(0,-.72),(1,.72)]:
            put(beat+offset,guitar(note,length,voice,True),.105,pan)
            put(beat+offset,guitar(note+7,length,voice,True),.065,pan)
    if bar%4==3:
        for offset in [3.25,3.5,3.75]:put(beat+offset,snare(1),.14)
    active_mix=intensity
    for offset,interval,length in riff:
        note=root+interval+12
        for voice,pan in [(0,-.85),(1,.85)]:
            put(beat+offset,guitar(note,length,voice,False),.075,pan)
            put(beat+offset,guitar(note+7,length,voice,False),.042,pan)
    for offset in [.25,1.25,2.25,3.25]:
        put(beat+offset,hat(offset>3),.04,.28)
    if section in (1,2,4,5):
        for offset,note,length in lead_phrases[bar%4]:
            put(beat+offset,guitar(note,length,0,False),.13,.1)
            put(beat+offset+.5,guitar(note,length,1,False),.025,-.45)
    else:
        for offset in [0,2.5]:
            put(beat+offset,guitar(root+19,.88,1,False),.07,.35)
# Shared headroom preserves stem balance. A short seam fade avoids clicks.
peak=float(np.max(np.abs(mix)+np.abs(intensity)))
gain=.86/max(peak,1e-6)
OUT.mkdir(parents=True,exist_ok=True)
for name,stem in [("soundtrack",mix),("soundtrack_intensity",intensity)]:
    stem*=gain
    fade=round(.008*SR)
    stem[-fade:]+=np.linspace(0,1,fade,dtype=np.float32)[:,None]*(stem[0]-stem[-1])
    rms=float(np.sqrt(np.mean(stem**2)))
    assert np.isfinite(stem).all() and rms>.005
    with tempfile.TemporaryDirectory() as tmp:
        wav=Path(tmp)/"stem.wav"
        with wave.open(str(wav),"wb") as f:
            f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
            f.writeframes(np.asarray(np.clip(stem,-1,1)*32767,dtype="<i2").tobytes())
        target=OUT/(name+".ogg")
        subprocess.run(["ffmpeg","-v","error","-y","-i",str(wav),"-c:a","libvorbis","-q:a","5",str(target)],check=True)
        length=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",str(target)]))
        assert abs(length-N/SR)<.03 and target.stat().st_size>10000
        print(f"REDLINE RIOT {name}: {BPM} BPM, {length:.2f}s, RMS {rms:.3f}")
