/* Pure deterministic chart and judgment engine. */
const rhythmCore = function rhythmCore(){
  const songs=[
    {id:"afterhours",title:"AFTER HOURS",genre:"Electro disco",bpm:120,bars:24,root:45,seed:11},
    {id:"static",title:"STATIC FEVER",genre:"Synth funk",bpm:140,bars:24,root:48,seed:29},
    {id:"overdrive",title:"OVERRIDE",genre:"Breakbeat",bpm:166,bars:28,root:43,seed:47}
  ];
  const levels={easy:{step:1,window:0.18,guard:8},normal:{step:0.5,window:0.145,guard:4},hard:{step:0.25,window:0.115,guard:4}};
  const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
  function chart(song,difficulty){
    const config=levels[difficulty],beat=60/song.bpm,out=[];
    const total=song.bars*4;
    let seed=song.seed;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
    let last=-1;
    for(let b=4;b<total-1;b+=config.step){
      const bar=Math.floor(b/4),sub=b%1;
      if(sub&&rand()>(difficulty==="hard"?(bar%8>=4?0.62:0.35):0.65))continue;
      if(!sub&&b%config.guard===3&&bar%2===1){out.push({id:out.length,time:b*beat,lane:5,kind:"guard",beat:b});continue;}
      let lane=Math.floor(rand()*5);if(lane===last&&rand()<0.65)lane=(lane+1+Math.floor(rand()*4))%5;
      last=lane;out.push({id:out.length,time:b*beat,lane,kind:"hit",beat:b});
      if(difficulty!=="easy"&&!sub&&b%4===0&&bar%4===3)out.push({id:out.length,time:b*beat,lane:(lane+2)%5,kind:"hit",beat:b});
    }
    return out.sort((a,b)=>a.time-b.time||a.lane-b.lane);
  }
  class Run{
    constructor(song,difficulty){this.song=song;this.difficulty=difficulty;this.notes=chart(song,difficulty).map(n=>({...n,status:"pending"}));this.window=levels[difficulty].window;this.duration=song.bars*4*60/song.bpm;this.score=0;this.combo=0;this.maxCombo=0;this.perfect=0;this.good=0;this.miss=0;this.energy=100;this.cleared=0;this.cursor=0;this.events=[];}
    expire(t){while(this.cursor<this.notes.length&&this.notes[this.cursor].time<t-this.window){const n=this.notes[this.cursor++];if(n.status==="pending")this.fail(n);} }
    fail(n){if(n.status!=="pending")return;n.status="miss";this.miss++;this.combo=0;this.energy=clamp(this.energy-(n.kind==="guard"?8:3),0,100);this.events.push({type:"miss",note:n});}
    press(lane,t){
      this.expire(t);
      let best=null,error=Infinity;
      for(let i=this.cursor;i<this.notes.length;i++){const n=this.notes[i];if(n.time>t+this.window)break;if(n.status!=="pending"||n.lane!==lane)continue;const e=Math.abs(n.time-t);if(e<error){best=n;error=e;}}
      if(!best){this.combo=0;this.events.push({type:"empty",lane});return null;}
      const perfect=error<=this.window*0.43;best.status=perfect?"perfect":"good";this.combo++;this.maxCombo=Math.max(this.maxCombo,this.combo);if(perfect)this.perfect++;else this.good++;
      const multiplier=Math.min(4,1+Math.floor(this.combo/10));
      this.score+=(perfect?100:60)*multiplier;this.energy=clamp(this.energy+(best.kind==="guard"?2:0.7),0,100);if(best.kind==="hit")this.cleared++;
      const result={type:best.status,note:best,error,multiplier};this.events.push(result);return result;
    }
    accuracy(){return this.notes.length?100*(this.perfect+0.6*this.good)/this.notes.length:0;}
    drain(){return this.events.splice(0);}
  }
  return {songs,levels,chart,Run,clamp};
};
const Rhythm = rhythmCore();
if (typeof module !== "undefined") module.exports = Rhythm;
if (typeof globalThis !== "undefined") globalThis.Rhythm = Rhythm;
