(() => {
  "use strict";
  let ctx, master, filter, gains=[], sources=[], originalBuffers=null, localBuffer=null, generation=0;
  let enabled=false, adaptive=true, speed=0, paused=false, started=false, pending=false;
  const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
  const smooth=x=>{x=clamp(x,0,1);return x*x*(3-2*x);};
  function setup(){
    if(ctx)return;
    const AudioContextClass=window.AudioContext||window.webkitAudioContext;
    ctx=new AudioContextClass();
    master=ctx.createGain(); master.gain.value=0;
    filter=ctx.createBiquadFilter(); filter.type="lowpass";filter.frequency.value=20000;
    filter.connect(master);master.connect(ctx.destination);
  }
  function fade(){
    if(!ctx)return;
    const intensity=smooth((speed-35)/135);
    const now=ctx.currentTime;
    master.gain.setTargetAtTime(enabled?(adaptive?.34+.28*intensity:.42):0,now,.28);
    if(gains.length>1)gains[1].gain.setTargetAtTime(adaptive?intensity:.55,now,.35);
    filter.frequency.setTargetAtTime(localBuffer&&adaptive?2200+17800*intensity:20000,now,.4);
  }
  function stopSources(){
    for(const source of sources){try{source.stop();}catch(_){}source.disconnect();}
    for(const gain of gains)gain.disconnect();
    sources=[];gains=[];started=false;
  }
  function playBuffers(buffers){
    stopSources();
    const when=ctx.currentTime+.08;
    for(let i=0;i<buffers.length;i++){
      const source=ctx.createBufferSource(),gain=ctx.createGain();
      source.buffer=buffers[i];source.loop=true;
      source.loopEnd=buffers[0].duration;
      gain.gain.value=i===0?1:0;
      source.connect(gain);gain.connect(filter);
      source.start(when);sources.push(source);gains.push(gain);
    }
    started=true;fade();
  }
  async function loadOriginal(){
    if(originalBuffers)return originalBuffers;
    originalBuffers=await Promise.all(["soundtrack.ogg","soundtrack_intensity.ogg"].map(async name=>{
      const response=await fetch(new URL(name,document.baseURI));
      if(!response.ok)throw Error("Soundtrack file unavailable");
      return ctx.decodeAudioData(await response.arrayBuffer());
    }));
    return originalBuffers;
  }
  async function start(){
    if(!enabled||paused||started||pending)return;
    pending=true;const token=generation;
    try{
      setup();await ctx.resume();
      const buffers=localBuffer?[localBuffer]:await loadOriginal();
      if(token===generation&&!started){playBuffers(buffers);if(paused)await ctx.suspend();}
    }catch(error){console.warn("Soundtrack unavailable",error);}
    finally{pending=false;}
  }
  function chooseLocal(){
    const input=document.createElement("input");
    input.type="file";input.accept="audio/*,.mp3,.ogg,.wav,.m4a,.flac";
    input.onchange=async()=>{
      const file=input.files&&input.files[0];if(!file)return;
      try{
        setup();
        const decoded=await ctx.decodeAudioData(await file.arrayBuffer());
        generation++;localBuffer=decoded;stopSources();
        if(!paused)await ctx.resume();
        playBuffers([decoded]);
        if(paused)await ctx.suspend();
      }catch(error){console.warn("Cannot decode local audio",error);window.alert("This audio file could not be opened by your browser.");}
    };
    input.click();
  }
  async function restoreOriginal(){
    generation++;localBuffer=null;stopSources();pending=false;
    if(!paused)start();
  }
  window.velocityMusic={
    start,chooseLocal,restoreOriginal,
    configure(on,adapt,value){enabled=Boolean(on);adaptive=Boolean(adapt);speed=Number.isFinite(value)?Math.max(0,value):0;fade();},
    setEnabled(value){enabled=Boolean(value);fade();},
    setSpeed(value){speed=Number.isFinite(value)?Math.max(0,value):0;fade();},
    setPaused(value){
      paused=Boolean(value);
      if(!ctx)return;
      if(paused)ctx.suspend().catch(()=>{});
      else ctx.resume().then(()=>{if(!started)start();}).catch(()=>{});
    }
  };
  window.addEventListener("pointerdown",start,{capture:true,passive:true});
  window.addEventListener("keydown",start,{capture:true});
  window.addEventListener("touchend",start,{capture:true,passive:true});
})();
