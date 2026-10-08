import {readFile} from 'node:fs/promises';
import {transform} from 'esbuild';
import vm from 'node:vm';
import assert from 'node:assert/strict';
let handler,mode='success',calls=[];
const source=await transform(await readFile('supabase/functions/diesel-login/index.ts','utf8'),{loader:'ts'});
vm.runInNewContext(source.code,{Request,Response,AbortSignal,Set,JSON,Number,Deno:{env:{get:k=>({SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'server-secret',SUPABASE_ANON_KEY:'public-key'})[k]},serve:fn=>handler=fn},fetch:async(url,opts)=>{
 const body=JSON.parse(opts.body);calls.push({url,opts,body});
 if(url.includes('/rpc/'))return Response.json(mode==='rate'?{status:429}:{status:200,email:mode==='missing'?null:'person@example.com'});
 return Response.json(mode==='wrong'?{error:'wrong'}:{access_token:'session-token',refresh_token:'refresh-token',user:{email:'person@example.com'}},{status:mode==='wrong'?400:200});
}});
const request=(body,origin='https://abencoada-agricola.github.io')=>new Request('https://db.example/functions/v1/diesel-login',{method:'POST',headers:{origin,'Content-Type':'application/json','x-forwarded-for':'192.0.2.10'},body:JSON.stringify(body)});
let result=await handler(request({username:' OPERADOR ',password:'test-password'}));assert.equal(result.status,200);assert.deepEqual(await result.json(),{access_token:'session-token',refresh_token:'refresh-token'});
assert.equal(calls[0].body.login_name,'operador');assert.equal(calls[0].body.request_ip,'192.0.2.10');assert.equal(calls[0].opts.headers.apikey,'server-secret');assert.equal(calls[1].opts.headers.apikey,'public-key');assert.equal(calls[1].body.email,'person@example.com');
for(const failure of ['missing','wrong']){mode=failure;result=await handler(request({username:'operador',password:'test-password'}));assert.equal(result.status,401);assert.equal((await result.json()).error,'Usuário ou senha inválidos.')}
mode='rate';calls=[];assert.equal((await handler(request({username:'operador',password:'test-password'}))).status,429);assert.equal(calls.length,1);
assert.equal((await handler(request({username:'operador',password:'test-password'},'https://other.example'))).status,403);
assert.equal((await handler(request({username:'ab',password:'test-password'}))).status,401);
result=await handler(new Request('https://db.example',{method:'OPTIONS',headers:{origin:'https://abencoada-agricola.github.io'}}));assert.equal(result.status,204);assert.ok(result.headers.get('Access-Control-Allow-Headers').includes('authorization'));
console.log('Login por usuário, sessão, limite e privacidade: testes aprovados.');
