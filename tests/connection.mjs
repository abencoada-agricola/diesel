import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
let methods,mode='network';
const source=(await readFile('web/backend.js','utf8')).replace(/^import .*;$/gm,'').replaceAll('export ','');
// Return exported functions without touching browser or native application state.
const context={config:{url:'https://db.example',publishableKey:'public',loginKey:'public-jwt'},createClient:()=>({auth:{getSession:async()=>({data:{session:{access_token:'token'}}}),setSession:async()=>({})},rpc:()=>({abortSignal:async()=>{throw new TypeError('Failed to fetch')}})}),fetch:async()=>{if(mode==='network')throw new TypeError('Failed to fetch');if(mode==='timeout')throw Object.assign(new Error('timeout'),{name:'AbortError'});return Response.json({error:'invalid'},{status:401})},Response,AbortController,URLSearchParams,setTimeout,clearTimeout};
vm.runInNewContext(source+'\nmethods={signIn,api};',context);methods=context.methods;
for(mode of ['network','timeout'])await assert.rejects(methods.signIn('admin','test-only'),/Conecte o celular à internet/);
mode='invalid';await assert.rejects(methods.signIn('admin','test-only'),/Usuário ou senha inválidos/);
await assert.rejects(methods.api('session'),/registros continuam salvos/);
console.log('Connection failures show Portuguese guidance; invalid credentials remain distinct.');
