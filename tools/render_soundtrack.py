#!/usr/bin/env python3
"""Vector Velocity — NIGHT CIRCUIT. Original dark melodic industrial drum-and-bass score.
All instruments and patterns synthesized offline; no borrowed samples.
Requires numpy and ffmpeg/libvorbis.
"""
from pathlib import Path
from functools import lru_cache
import subprocess, tempfile, wave
import numpy as np

SR=44100
BPM=174
BEAT=60/BPM
BARS=112
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

# NIGHT CIRCUIT — 112 bars with an original recurring theme, two drops,
# a melodic bridge and a final reprise. Drum patterns change independently
# of harmonic phrases. The sound remains continuous without restarting.
@lru_cache(maxsize=80)
def atmosphere(note,beats):
    dur=beats*BEAT
    t=time(dur)
    p=TAU*hz(note)*t
    voice=(.56*np.sin(p)+.23*np.sin(p*1.004)+.15*np.sin(2*p)+.06*np.sin(3*p))
    return voice*envelope(t,.13,.30,dur)*(.83+.17*np.sin(TAU*.72*t))

@lru_cache(maxsize=128)
def pulse(note,beats):
    dur=beats*BEAT
    t=time(dur)
    p=TAU*hz(note)*t
    # Warm filtered moving bass, deliberately no high whine.
    mod=(.22+.18*np.sin(TAU*3.2*t))*np.exp(-t*1.6)
    sig=.7*np.sin(p)+.22*np.sin(2*p+mod*np.sin(3*p))+.08*np.sin(3*p)
    return np.tanh(sig*1.1)*envelope(t,.008,.045,dur)

# E minor with longer eight-bar progressions and a distinct major-key bridge.
progressions=[
 [(40,[52,55,59,66]),(40,[52,55,59,64]),(36,[52,55,60,64]),(36,[52,55,60,67]),(43,[55,59,62,66]),(43,[55,59,62,67]),(38,[54,57,62,66]),(39,[51,54,59,63])],
 [(40,[52,55,59,64]),(38,[54,57,62,66]),(36,[52,55,60,64]),(36,[52,55,60,67]),(33,[52,57,60,64]),(33,[52,57,60,65]),(35,[54,59,62,66]),(35,[51,54,59,63])],
 [(43,[55,59,62,69]),(43,[55,59,62,67]),(38,[54,57,62,66]),(38,[54,57,62,69]),(40,[52,55,59,66]),(40,[52,55,59,64]),(36,[52,55,60,67]),(35,[51,54,59,66])]
]
patterns=[
 ([0,2.5],[1,3]),
 ([0,1.75,2.5,3.5],[1,3]),
 ([0,.75,2,2.75],[1,2.5,3.5]),
 ([0,1.5,2.75],[2]),
 ([0,.75,1.5,2.5,3.25],[1,3])
]
themes=[
 [(0,76,1.1),(1.5,79,.42),(2.0,78,.8),(3.0,74,.8)],
 [(0,71,1.4),(1.75,74,.65),(2.5,76,1.2)],
 [(0,79,.8),(1,81,.42),(1.5,79,.75),(2.5,78,1.2)],
 [(0,74,.75),(1,71,.75),(2,72,1.65)],
 [(0,76,.75),(1,79,.75),(2,83,1.4)],
 [(0,81,.75),(1,79,.6),(2,78,1.6)],
 [(0,74,1.1),(1.5,76,.45),(2,78,1.6)],
 [(0,75,.75),(1,78,.75),(2,71,1.6)]
]
# Intro, build, first drop, variation, bridge, second drop, contrast,
# reprise, finale, and a continuous handoff to the intro.
sections=[(0,0),(0,1),(1,1),(1,2),(2,2),(1,3),(2,0),(2,3),(1,4),(1,2),(0,3),(1,4),(2,4),(0,1)]
for bar in range(BARS):
    beat=bar*4
    part=bar//8
    prog,pattern=sections[part]
    root,chord=progressions[prog][bar%8]
    quiet=part in (0,5,6,10,13)
    drop=part in (2,3,4,8,9,11,12)
    ks,ss=patterns[pattern]
    if part==0 and bar<4:ks=[0,2.5]
    for k in ks:
        put(beat+k,kick(drop),.48 if quiet else .60 if k==0 else .46)
    for k in ss:
        put(beat+k,snare(),.36 if quiet else .52)
    ghosts=[.75,2.25,3.75] if drop else [1.75,3.75]
    for k in ghosts:
        put(beat+k,snare(1),.09 if quiet else .15,(-.25 if k<2 else .25))
    for step in range(16 if drop else 8):
        offset=step*(.25 if drop else .5)
        put(beat+offset,hat(step%8==6),.043 if step%2==0 else .022,(-.40 if step%2 else .40))
    if bar%4==3 and not quiet:
        for k in (3.25,3.5,3.75):
            put(beat+k,snare(1),.11+.06*(k-3.25))
    # Sustained harmony and a syncopated bass line, not constant metal chugs.
    for n,note in enumerate(chord):
        put(beat,atmosphere(note,4.5),.065 if drop else .105,(-.62 if n%2==0 else .62))
    bass_pattern=[(0,0,1.36),(1.5,0,.66),(2.25,7,.66),(3,0,.85)] if quiet else ([(0,0,.68),(.75,0,.65),(1.5,12,.42),(2,0,.92),(3,7,.42),(3.5,0,.43)] if bar%2==0 else [(0,0,1.18),(1.25,7,.45),(1.75,0,.42),(2.25,0,.68),(3,12,.43),(3.5,0,.43)])
    for offset,interval,length in bass_pattern:
        put(beat+offset,pulse(root-12+interval,length),.43 if drop else .34)
        if drop:
            put(beat+offset,bass(root+interval,length,True),.16)
    # Power chords only at dramatic accents; leave room for percussion.
    if drop and part not in (4,9):
        for offset,length in [(0,.64),(2.5,.64)] if bar%2==0 else [(1.5,.48),(3,.65)]:
            for voice,pan in [(0,-.75),(1,.75)]:
                put(beat+offset,guitar(root,length,voice,True),.12,pan)
                put(beat+offset,guitar(root+7,length,voice,True),.075,pan)
    if part in (1,3,4,6,8,9,11,12):
        theme=themes[bar%8]
        for offset,note,length in theme:
            n=note-12 if part in (1,6) else note
            sig=lead(n,length)
            put(beat+offset,sig,.075 if quiet else .10,.08)
            put(beat+offset+.75,sig,.019,-.45)
            if part in (11,12) and offset in (0,2):
                put(beat+offset,atmosphere(n-12,length),.055,.45)
    if bar%8==7 and part!=13:
        tt=time(.65)
        sweep=np.convolve(rng.normal(0,1,len(tt)),[.1,.2,.4,.2,.1],mode="same")
        put(beat+2.0,sweep*envelope(tt,.45,.06,.65),.07)
# Loudness control: intentional instrument distortion, not clipped final audio.
# Keep drum transients and dynamics rather than hard-saturating the
# complete mix. Soft limiting only affects the loudest peaks.
mix*=.75/max(float(np.percentile(np.abs(mix),99.5)),1e-6)
mix=np.where(np.abs(mix)>.72,np.sign(mix)*(.72+.15*np.tanh((np.abs(mix)-.72)/.15)),mix)
peak=float(np.max(np.abs(mix)))
mix*=.88/max(peak,1e-6)
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
    print(f"NIGHT CIRCUIT: {BPM} BPM, {length:.2f}s, RMS {rms:.3f}, {target.stat().st_size:,} bytes")
