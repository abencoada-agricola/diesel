import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';
import vm from 'node:vm';
import assert from 'node:assert/strict';
let handler,mode='create',writes=[];
const source=await transform(await readFile('supabase/functions/diesel-login/index.ts','utf8'),{loader:'ts'});
vm.runInNewContext(source.code,{Request,Response,AbortSignal,Set,JSON,Number,Array,encodeURIComponent,Deno:{env:{get:k=>({SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'server-secret',SUPABASE_ANON_KEY:'public-key'})[k]},serve:fn=>handler=fn},fetch:async(url,opts)=>{
 if(url.endsWith('/rpc/diesel_admin')){
  assert.equal(opts.headers.apikey,'public-key');
  return Response.json(opts.headers.Authorization==='Bearer manager-token'?{members:[{email:'operator@example.com'}]}:{error:'Acesso restrito',status:403});
 }
 assert.equal(opts.headers.Authorization,'Bearer server-secret');
 if(!opts.method)return Response.json({users:mode==='existing'?[{id:'account-id',email:'operator@example.com'}]:[]});
 writes.push({url,opts,body:JSON.parse(opts.body)});return Response.json({id:'account-id'});
}});
const request=(body,token='manager-token')=>new Request('https://db.example/functions/v1/diesel-login',{method:'POST',headers:{origin:'https://abencoada-agricola.github.io','Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({action:'team-password',...body})});
const body={email:'operator@example.com',password:'test-password'};
for(const token of ['operator-token','forged-token','public-key','']){assert.equal((await handler(request(body,token))).status,403);assert.equal(writes.length,0)}
assert.equal((await handler(request({...body,email:'outsider@example.com'}))).status,422);assert.equal(writes.length,0);
assert.equal((await handler(request({...body,password:'12345'}))).status,422);assert.equal(writes.length,0);
let result=await handler(request(body));assert.deepEqual(await result.json(),{saved:true,created:true});assert.equal(writes.length,1);assert.equal(writes[0].opts.method,'POST');assert.deepEqual(writes[0].body,{email:body.email,password:body.password,email_confirm:true});
mode='existing';writes=[];result=await handler(request(body));assert.deepEqual(await result.json(),{saved:true,created:false});assert.equal(writes[0].opts.method,'PUT');assert.ok(writes[0].url.endsWith('/account-id'));assert.deepEqual(writes[0].body,{password:body.password});
console.log('Team passwords: manager authorization, membership, validation, create and update passed.');
