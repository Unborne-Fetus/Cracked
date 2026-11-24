(function browserGame(){
"use strict";
const {songs,levels,Run,clamp}=globalThis.Rhythm;
const $=id=>document.getElementById(id);
const canvas=$("stage"),ctx=canvas.getContext("2d"),menu=$("menu"),result=$("result"),pause=$("pause"),hud=$("hud"),touch=$("touch");
const colors=["#6bfab0","#ff648b","#ffda65","#65baff","#bd85ff","#f8f9ff"],keys=["A","S","D","F","G","SPACE"];
const keymap={KeyA:0,KeyS:1,KeyD:2,KeyF:3,KeyG:4,Space:5};
let song=songs[0],difficulty="normal",run=null,state="menu",audio=null,master=null,noise=null,origin=0,scheduled=0,pausedAt=0,offset=0,volume=0.7,visualTime=0,attack=null,feedback="",feedbackUntil=0,particles=[],rings=[],held=new Set(),padPrev=[],width=1280,height=720,dpr=1;
let bests={};try{bests=JSON.parse(localStorage.getItem("beatbreak.records")||"{}");offset=Number(localStorage.getItem("beatbreak.offset")||0);volume=Number(localStorage.getItem("beatbreak.volume")||0.7);}catch{}
if(!Number.isFinite(offset))offset=0;if(!Number.isFinite(volume))volume=.7;
$("offset").value=String(clamp(offset*1000,-200,200));$("volume").value=String(clamp(volume,0,1)*100);
function saveSetting(){try{localStorage.setItem("beatbreak.offset",String(offset));localStorage.setItem("beatbreak.volume",String(volume));}catch{}}
$("offset").oninput=e=>{offset=Number(e.target.value)/1000;$("offsetValue").textContent=`${Math.round(offset*1000)} ms`;saveSetting();};
$("volume").oninput=e=>{volume=Number(e.target.value)/100;if(master&&audio)master.gain.setTargetAtTime(volume*.48,audio.currentTime,.05);saveSetting();};
$("offsetValue").textContent=`${Math.round(offset*1000)} ms`;
function populate(){
 $("songs").replaceChildren();
 for(const s of songs){const b=document.createElement("button");b.className="song"+(s===song?" selected":"");b.innerHTML=`<strong>${s.title}</strong><span>${s.genre} / ${s.bpm} BPM</span><small>${Math.round(s.bars*240/s.bpm)} SEC</small>`;b.onclick=()=>{song=s;populate();};$("songs").append(b);}
 for(const b of document.querySelectorAll("[data-level]"))b.classList.toggle("selected",b.dataset.level===difficulty);
 $("record").textContent=`BEST SCORE  ${Number(bests[song.id+":"+difficulty]||0).toLocaleString()}`;
}
for(const b of document.querySelectorAll("[data-level]"))b.onclick=()=>{difficulty=b.dataset.level;populate();};
populate();
function resize(){const r=canvas.getBoundingClientRect();width=r.width||1280;height=r.height||720;dpr=Math.min(2,window.devicePixelRatio||1);canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);}
window.addEventListener("resize",resize);resize();
function now(){return audio?audio.currentTime-origin:0;}
function hz(n){return 440*Math.pow(2,(n-69)/12);}
function tone(t,f,d,g,type="triangle",end=f){
 const osc=audio.createOscillator(),amp=audio.createGain();osc.type=type;osc.frequency.setValueAtTime(f,t);osc.frequency.exponentialRampToValueAtTime(Math.max(20,end),t+d);amp.gain.setValueAtTime(.0001,t);amp.gain.exponentialRampToValueAtTime(g,t+.008);amp.gain.exponentialRampToValueAtTime(.0001,t+d);osc.connect(amp).connect(master);osc.start(t);osc.stop(t+d+.015);
}
function hiss(t,d,g,f){
 const src=audio.createBufferSource(),filter=audio.createBiquadFilter(),amp=audio.createGain();src.buffer=noise;filter.type="highpass";filter.frequency.value=f;amp.gain.setValueAtTime(g,t);amp.gain.exponentialRampToValueAtTime(.0001,t+d);src.connect(filter).connect(amp).connect(master);src.start(t);src.stop(t+d+.015);
}
function schedule(){
 if(state!=="playing"||!audio)return;
 const step=60/song.bpm/4,total=song.bars*16;
 while(scheduled<total&&origin+scheduled*step<audio.currentTime+.45){
  const i=scheduled++,t=origin+i*step,bar=Math.floor(i/16),p=i%16,chord=[0,3,5,7][Math.floor(bar/2)%4],root=song.root+chord;
  if(t<audio.currentTime-.02)continue;
  const at=Math.max(t,audio.currentTime+.002);
  if(p%4===0)tone(at,125,.18,.55,"sine",43);
  if(p===4||p===12){hiss(at,.15,.22,1200);tone(at,170,.09,.10,"triangle",85);}
  if(p%2===0)hiss(at,.045,p%4===2?.095:.047,6500);
  if(p===0||p===3||p===6||p===8||p===11||p===14)tone(at,hz(root-12+(p===14?7:0)),step*2.6,.16,"sawtooth");
  if(p===0||p===8)for(const n of [0,3,7,10])tone(at,hz(root+n),step*6,.035,"triangle");
  if(bar>=4&&[1,5,7,10,13,15].includes(p)){const melody=[0,7,12,10,3,7,15,12];tone(at,hz(root+12+melody[(i+bar)%melody.length]),step*1.7,.065,song.id==="overdrive"?"square":"triangle");}
 }
}
async function start(){
 if(state==="starting")return;state="starting";
 try{
  if(audio)await audio.close();
  const AC=window.AudioContext||window.webkitAudioContext;if(!AC)throw Error("Web Audio is unavailable.");
  audio=new AC();await audio.resume();
  master=audio.createGain();master.gain.value=volume*.48;const comp=audio.createDynamicsCompressor();master.connect(comp).connect(audio.destination);
  noise=audio.createBuffer(1,Math.ceil(audio.sampleRate*.2),audio.sampleRate);const data=noise.getChannelData(0);for(let i=0;i<data.length;i++)data[i]=Math.random()*2-1;
  run=new Run(song,difficulty);origin=audio.currentTime+1.6;scheduled=0;pausedAt=0;particles=[];rings=[];attack=null;feedback="";held.clear();state="playing";menu.hidden=true;result.hidden=true;pause.hidden=true;hud.hidden=false;touch.hidden=false;$("songName").textContent=song.title;updateHUD();schedule();
 }catch(e){state="menu";menu.hidden=false;$("error").textContent="Audio could not start. "+e.message;}
}
function goMenu(){state="menu";if(audio){audio.close().catch(()=>{});audio=null;}run=null;held.clear();menu.hidden=false;result.hidden=true;pause.hidden=true;hud.hidden=true;touch.hidden=true;populate();}
async function togglePause(){
 if(state==="playing"){pausedAt=now();state="paused";pause.hidden=false;held.clear();await audio.suspend();}
 else if(state==="paused"){await audio.resume();state="playing";pause.hidden=true;}
}
function finish(){
 if(!run||state!=="playing")return;
 run.expire(run.duration+1);state="result";if(audio)audio.suspend().catch(()=>{});hud.hidden=true;touch.hidden=true;pause.hidden=true;result.hidden=false;
 const acc=run.accuracy(),grade=acc>=97?"S":acc>=88?"A":acc>=75?"B":acc>=60?"C":"D";
 const k=song.id+":"+difficulty;const old=Number(bests[k]||0);if(run.score>old){bests[k]=run.score;try{localStorage.setItem("beatbreak.records",JSON.stringify(bests));}catch{}}
 $("grade").textContent=grade;$("resultTitle").textContent=run.score>old?"NEW HIGH SCORE":"SET COMPLETE";$("resultScore").textContent=run.score.toLocaleString();
 $("resultStats").textContent=`${acc.toFixed(1)}% accuracy  •  ${run.maxCombo} max combo  •  ${run.perfect} perfect  •  ${run.good} good  •  ${run.miss} missed`;
}
$("start").onclick=start;$("retry").onclick=start;$("quit").onclick=goMenu;$("resultMenu").onclick=goMenu;$("resume").onclick=togglePause;$("pauseButton").onclick=togglePause;
document.addEventListener("visibilitychange",()=>{if(document.hidden&&state==="playing")togglePause();});
function press(lane){
 if(state!=="playing"||!run)return;
 const t=now()+offset;if(t<0)return;
 const hit=run.press(lane,t);if(hit){const good=hit.type==="perfect";feedback=hit.note.kind==="guard"?(good?"PERFECT DODGE":"DODGE"):(good?"PERFECT":"GOOD");feedbackUntil=performance.now()+500;attack={lane,at:performance.now(),guard:lane===5};rings.push({at:performance.now(),lane});
  for(let i=0;i<16;i++){const angle=Math.random()*Math.PI*2;particles.push({x:0,y:0,vx:Math.cos(angle)*(60+Math.random()*220),vy:Math.sin(angle)*(60+Math.random()*220),life:.35+Math.random()*.3,color:colors[lane],lane});}
 }
 updateHUD();
}
window.addEventListener("keydown",e=>{if(e.code==="Escape"){e.preventDefault();if(!e.repeat)togglePause();return;}if(e.code==="Enter"&&!e.repeat){if(state==="menu"||state==="result")start();return;}if(!(e.code in keymap))return;if(state==="playing"||state==="paused")e.preventDefault();if(e.repeat||held.has(e.code))return;held.add(e.code);press(keymap[e.code]);});
window.addEventListener("keyup",e=>held.delete(e.code));window.addEventListener("blur",()=>held.clear());
for(const b of touch.querySelectorAll("[data-lane]")){b.addEventListener("pointerdown",e=>{e.preventDefault();b.setPointerCapture(e.pointerId);b.classList.add("held");press(Number(b.dataset.lane));});for(const ev of ["pointerup","pointercancel","lostpointercapture"])b.addEventListener(ev,()=>b.classList.remove("held"));}
function pads(){const p=Array.from(navigator.getGamepads?.()||[]).find(Boolean);if(!p){padPrev=[];return;}const mapping=[14,0,1,2,3,5];for(let i=0;i<mapping.length;i++){const idx=mapping[i];if(p.buttons[idx]?.pressed&&!padPrev[idx])press(i);}if(p.buttons[9]?.pressed&&!padPrev[9])togglePause();padPrev=p.buttons.map(b=>b.pressed);}
function updateHUD(){if(!run)return;$("score").textContent=run.score.toLocaleString();$("combo").textContent=run.combo+"×";$("energy").style.width=run.energy+"%";$("progress").style.width=clamp(now()/run.duration*100,0,100)+"%";$("mult").textContent=Math.min(4,1+Math.floor(run.combo/10))+"× MULTIPLIER";}
function line(a,b,c,d,color,w=1){ctx.strokeStyle=color;ctx.lineWidth=w;ctx.beginPath();ctx.moveTo(a,b);ctx.lineTo(c,d);ctx.stroke();}
function poly(points,fill,stroke){ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();if(fill){ctx.fillStyle=fill;ctx.fill();}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1.5;ctx.stroke();}}
function ellipse(x,y,rx,ry,color){ctx.beginPath();ctx.ellipse(x,y,rx,ry,0,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();}
function figure(x,y,s,color,phase,player=false,stagger=0){
 const sway=Math.sin(phase)*4*s,step=Math.cos(phase)*7*s,lean=stagger*12*s;
 ellipse(x,y+5*s,24*s,7*s,"#0008");ctx.save();ctx.translate(x+lean,y+sway);ctx.scale(s,s);
 ctx.lineCap="round";line(-7,-30,-13-step,-5,color,8);line(7,-30,13+step,-5,color,8);
 poly([[-13,-59],[13,-59],[11,-30],[-11,-30]],player?"#e7faff":"#252944",color);
 line(-12,-55,-25,-40-stagger*10,color,8);line(12,-55,25+stagger*12,-40-stagger*7,color,8);
 ellipse(0,-70,12,13,player?"#edfaff":"#252944");line(-7,-71,7,-71,color,3);ctx.restore();
}
function draw(dt){
 ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,width,height);
 const w=width,h=height,t=run?(state==="paused"?pausedAt:now()):visualTime,beat=60/song.bpm,phase=t/beat*Math.PI*2,pulse=Math.exp(-Math.pow((t/beat-Math.round(t/beat))*5,2));
 const bg=ctx.createLinearGradient(0,0,0,h);bg.addColorStop(0,"#080819");bg.addColorStop(.55,"#16102b");bg.addColorStop(1,"#060611");ctx.fillStyle=bg;ctx.fillRect(0,0,w,h);
 const cx=w*.5,arenaBottom=h*.49,horizon=h*.17;
 for(let i=0;i<7;i++){const x=w*(i+.5)/7,reach=Math.sin(phase*.5+i)*w*.07;poly([[x-3,0],[x+3,0],[cx+reach+w*.17,arenaBottom],[cx+reach-w*.17,arenaBottom]],`rgba(${i%2?"100,75,255":"255,45,145"},${.025+pulse*.035})`);}
 for(let row=0;row<7;row++){const z=row/7,y=horizon+(arenaBottom-horizon)*z*z;line(w*.05*(1-z)+cx*(1-z)*.3,y,w-w*.05*(1-z)-cx*(1-z)*.3,y,"#8b65ff35",1);}
 for(let i=-6;i<=6;i++)line(cx+i*w*.025,horizon,cx+i*w*.105,arenaBottom,"#8b65ff33",1);
 const scale=Math.max(.6,Math.min(1.6,h/580)),playerX=cx,playerY=h*.43;
 const age=attack?(performance.now()-attack.at)/300:2;
 const move=age<1?Math.sin(age*Math.PI)*18*scale:0;
 for(let i=0;i<5;i++){const x=cx+(i-2)*w*.125,y=h*.34+Math.abs(i-2)*h*.022;figure(x,y,scale*.85,colors[i],phase+i*.65,false,attack&&attack.lane===i&&age<1?Math.sin(age*Math.PI):0);}
 figure(playerX+(attack&&age<1&&!attack.guard?(attack.lane-2)*move:0),playerY-(attack?.guard&&age<1?move:0),scale*1.15,"#82faff",phase,true,age<1?Math.sin(age*Math.PI):0);
 rings=rings.filter(r=>performance.now()-r.at<420);for(const r of rings){const a=(performance.now()-r.at)/420;ctx.strokeStyle=colors[r.lane]+Math.round((1-a)*180).toString(16).padStart(2,"0");ctx.lineWidth=3;ctx.beginPath();ctx.ellipse(cx,playerY,15+a*w*.18,5+a*h*.06,0,0,Math.PI*2);ctx.stroke();}
 for(const p of particles){p.life-=dt;p.x+=p.vx*dt;p.y+=p.vy*dt;ctx.globalAlpha=clamp(p.life*2,0,1);ctx.fillStyle=p.color;ctx.fillRect(cx+p.x,playerY-45*scale+p.y,4,4);}ctx.globalAlpha=1;particles=particles.filter(p=>p.life>0);
 if(state==="menu"||state==="starting")return;
 const top=h*.47,bottom=h*.88,trackW=Math.min(w*.87,760),farW=trackW*.38,nearX=cx-trackW/2,farX=cx-farW/2;
 function point(l,z){const widthAt=farW+(trackW-farW)*z;return [cx-widthAt/2+widthAt*(l/6),top+(bottom-top)*z];}
 poly([[farX,top],[farX+farW,top],[nearX+trackW,bottom],[nearX,bottom]],"#090c20e8","#6a5ea8");
 for(let i=0;i<=6;i++){const a=point(i,0),b=point(i,1);line(...a,...b,"#6962a05e",1);}
 const look=beat*4;
 if(run)for(let b=Math.floor(t/beat);b<=Math.ceil((t+look)/beat);b++){const z=1-(b*beat-t)/look;if(z<0||z>1)continue;const a=point(0,z),q=point(6,z);line(...a,...q,b%4===0?"#e4d9ff66":"#9487c53b",b%4===0?2:1);}
 if(run){for(let i=run.cursor;i<run.notes.length;i++){const n=run.notes[i];if(n.time>t+look)break;if(n.status!=="pending")continue;const z=1-(n.time-t)/look;if(z<0||z>1.04)continue;const p=point(n.lane+.5,z),q=point(n.lane+1,z),a=point(n.lane,z),rw=(q[0]-a[0])*.68,rh=6+z*10;
 ctx.shadowBlur=12;ctx.shadowColor=colors[n.lane];poly([[p[0]-rw/2,p[1]-rh/2],[p[0]+rw/2,p[1]-rh/2],[p[0]+rw*.43,p[1]+rh/2],[p[0]-rw*.43,p[1]+rh/2]],colors[n.lane],"#fff9");ctx.shadowBlur=0;
 }}
 for(let i=0;i<6;i++){const a=point(i,1),b=point(i+1,1),x=(a[0]+b[0])/2;ctx.strokeStyle=colors[i];ctx.lineWidth=3;ctx.strokeRect(a[0]+6,bottom-13,b[0]-a[0]-12,26);ctx.fillStyle=colors[i];ctx.font=`bold ${Math.max(12,h*.021)}px system-ui`;ctx.textAlign="center";ctx.fillText(keys[i],x,bottom+32);}
 if(performance.now()<feedbackUntil){ctx.font=`900 ${Math.max(20,h*.037)}px system-ui`;ctx.textAlign="center";ctx.fillStyle=feedback==="MISS"?"#ff668b":"#fff3a8";ctx.fillText(feedback,cx,top-13);}
 if(t<0&&state==="playing"){ctx.font="900 44px system-ui";ctx.fillStyle="#fff";ctx.textAlign="center";ctx.fillText("GET READY",cx,h*.22);}
}
let last=performance.now();function frame(ms){const dt=Math.min(.06,(ms-last)/1000);last=ms;visualTime+=dt;pads();if(state==="playing"&&run){schedule();const t=now();run.expire(t+offset);for(const e of run.drain()){if(e.type==="miss"){feedback="MISS";feedbackUntil=ms+400;}}updateHUD();if(t>=run.duration+.2)finish();}draw(state==="paused"?0:dt);requestAnimationFrame(frame);}requestAnimationFrame(frame);
})();
