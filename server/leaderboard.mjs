// Cloudflare Worker + D1. Anonymous public daily rankings; client-reported scores.
const headers = {"Content-Type":"application/json","Access-Control-Allow-Origin":"*","Access-Control-Allow-Methods":"GET, POST, OPTIONS","Access-Control-Allow-Headers":"Content-Type"};
const json = (data, status=200) => new Response(JSON.stringify(data),{status,headers});
const validDay = s => typeof s==="string" && /^\d{4}-\d{2}-\d{2}$/.test(s);
export default { async fetch(request, env) {
  const url = new URL(request.url);
  if(request.method==="OPTIONS") return new Response(null,{headers});
  if(url.pathname!=="/scores") return json({error:"Not found"},404);
  if(request.method==="GET"){
    const day = url.searchParams.get("day");
    if(!validDay(day)) return json({error:"Invalid date"},400);
    const rows = await env.DB.prepare("SELECT player,distance,speed,seconds FROM scores WHERE day=? ORDER BY distance DESC, seconds ASC LIMIT 50").bind(day).all();
    return json({scores:rows.results});
  }
  if(request.method!=="POST") return json({error:"Method not allowed"},405);
  if(Number(request.headers.get("content-length")||0)>2048) return json({error:"Too large"},413);
  let x; try { const raw=await request.text(); if(raw.length>2048)return json({error:"Too large"},413);x=JSON.parse(raw); } catch{return json({error:"Invalid JSON"},400);}
  if(!x||!validDay(x.day)||x.day!==new Date().toISOString().slice(0,10)||typeof x.player!=="string"||!/^Runner-[a-f0-9]{12}$/.test(x.player)||![x.distance,x.speed,x.seconds].every(Number.isFinite)||x.distance<0||x.speed<0||x.seconds<=0||x.distance>1e8||x.speed>1e6||x.seconds>86400||x.distance>x.speed*x.seconds+20) return json({error:"Invalid score"},400);
  await env.DB.prepare("INSERT INTO scores(day,player,distance,speed,seconds) VALUES(?,?,?,?,?) ON CONFLICT(day,player) DO UPDATE SET distance=excluded.distance,speed=excluded.speed,seconds=excluded.seconds WHERE excluded.distance>scores.distance").bind(x.day,x.player,x.distance,x.speed,x.seconds).run();
  const rank=await env.DB.prepare("SELECT 1+COUNT(*) AS rank FROM scores WHERE day=? AND distance>(SELECT distance FROM scores WHERE day=? AND player=?)").bind(x.day,x.day,x.player).first();
  const rows=await env.DB.prepare("SELECT player,distance,speed,seconds FROM scores WHERE day=? ORDER BY distance DESC,seconds ASC LIMIT 50").bind(x.day).all();
  return json({rank:rank.rank,scores:rows.results});
}};
