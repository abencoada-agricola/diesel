import { env } from 'cloudflare:workers';
import { access, rules, json } from '../../../lib/access';
import { validateRecord } from '../../../lib/validation';
export async function GET(request: Request) {
 const u=await access();if(!u)return json({error:'Entre para consultar os registros.'},401);
 const url=new URL(request.url);const id=url.searchParams.get('id');
 if(id){const r=await env.DB!.prepare('SELECT * FROM records WHERE id=?'+(u.role==='admin'?'':' AND user_id=?')).bind(...(u.role==='admin'?[id]:[id,u.userId])).first();return r?json(r):json({error:'Registro não encontrado.'},404);}
 const result=await env.DB!.prepare('SELECT id,fleet,date,operator,engine,elevator,km,start,end,liters,notes,created_at,received_at FROM records'+(u.role==='admin'?'':' WHERE user_id=?')+' ORDER BY received_at DESC').bind(...(u.role==='admin'?[]:[u.userId])).all();return json({records:result.results});
}
export async function POST(request: Request) {
 const u=await access();if(!u)return json({error:'Entre com uma conta autorizada para sincronizar.'},401);
 if (Number(request.headers.get('content-length')||0)>200000) return json({error:'Registro muito grande.'},413);
 let r: any;try{r=await request.json()}catch{return json({error:'Registro inválido.'},400)}
 if(!r||typeof r!=='object'||Array.isArray(r))return json({error:'Registro inválido.'},400);
 const existing=await env.DB!.prepare('SELECT user_id FROM records WHERE id=?').bind(String(r?.id||'')).first<any>();
 if(existing)return existing.user_id===u.userId?json({id:r.id,duplicate:true}):json({error:'Identificador já utilizado.'},409);
 r.operator=u.displayName;
 let error;try{error=validateRecord(r,await rules())}catch{error='Data ou registro inválido.'}if(error)return json({error},422);
 const f=await env.DB!.prepare('SELECT id FROM fleets WHERE id=? AND active=1').bind(r.fleet).first();if(!f)return json({error:'Esta frota não está ativa. Consulte o gestor.'},422);
 const now=new Date().toISOString();
 const result=await env.DB!.prepare('INSERT OR IGNORE INTO records(id,fleet,date,operator,user_id,engine,elevator,km,start,end,liters,signature,notes,created_at,received_at) SELECT ?,?,?,?,?,?,?,?,?,?,?,?,?,?,? WHERE NOT EXISTS (SELECT 1 FROM records WHERE fleet=? AND (engine>? OR elevator>? OR km>?))').bind(r.id,r.fleet,r.date,u.displayName,u.userId,r.engine,r.elevator,r.km,r.start,r.end,r.liters,u.displayName,r.notes,r.createdAt,now,r.fleet,r.engine,r.elevator,r.km).run();
 if(!result.meta.changes){const own=await env.DB!.prepare('SELECT user_id FROM records WHERE id=?').bind(r.id).first<any>();if(own?.user_id===u.userId)return json({id:r.id,duplicate:true});const readings=await env.DB!.prepare('SELECT MAX(engine) AS engine,MAX(elevator) AS elevator,MAX(km) AS km FROM records WHERE fleet=?').bind(r.fleet).first();return json({error:'Confira as informações: KM ou horímetros estão abaixo das últimas leituras da frota.',readings},422);}
 return json({id:r.id,receivedAt:now},201);
}
