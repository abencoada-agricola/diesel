import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base='http://127.0.0.1:5173';
const sign=await fetch(base+'/signin-with-chatgpt?return_to=/campo.html',{redirect:'manual'});
const cookie=sign.headers.getSetCookie().map(c=>c.split(';')[0]).join('; ');
async function call(path,body){const r=await fetch(base+'/api/'+path,{method:body?'POST':'GET',headers:{Cookie:cookie,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:r.status,data:await r.json()}}
assert.equal((await fetch(base+'/api/records')).status,401);
assert.equal((await call('session')).status,200);
assert.equal((await call('admin',{action:'fleet',id:'QA-01',name:'Máquina de teste local',type:'Trator'})).status,200);
const r={id:randomUUID(),fleet:'QA-01',date:'2026-10-07',operator:'Nome adulterado',engine:100,elevator:200,km:300,start:1000,end:1100,liters:100,notes:'Somente teste local',createdAt:new Date().toISOString()};
const first=await call('records',r);assert.equal(first.status,201,JSON.stringify(first));
const duplicate=await call('records',r);assert.equal(duplicate.status,200);assert.equal(duplicate.data.duplicate,true);
const detail=await call('records?id='+r.id);assert.equal(detail.data.signature,'Seedy');assert.equal(detail.data.operator,'Seedy');
for(const k of ['engine','elevator','km']){const bad=await call('records',{...r,id:randomUUID(),[k]:r[k]-1});assert.equal(bad.status,422,k);assert.ok(bad.data.readings)}
assert.equal((await call('records',{...r,id:randomUUID(),engine:null})).status,422);
assert.equal((await call('records',{...r,id:randomUUID(),end:999})).status,422);
const equal=await call('records',{...r,id:randomUUID()});assert.equal(equal.status,201);
const high={...r,id:randomUUID(),engine:110,elevator:210,km:310};assert.equal((await call('records',high)).status,201);
const stale=await call('records',{...r,id:randomUUID()});assert.equal(stale.status,422);
const list=(await call('records')).data.records;assert.equal(list.filter(x=>x.id===r.id).length,1);
console.log('PASS: autenticação, assinatura confirmada no servidor, campos obrigatórios, 3 bloqueios de leitura, igualdade permitida, conflito após nova leitura e idempotência.');
