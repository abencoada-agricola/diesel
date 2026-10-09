import {createClient} from './vendor.js';
import {config} from './config.js';
export const isConfigured=()=>/^https:\/\//.test(config.url)&&!!config.publishableKey;
const client=isConfigured()?createClient(config.url,config.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false,storageKey:'diesel-auth'}}):null;
export async function getAuthUserId(){return (await client.auth.getSession()).data.session?.user.id||null}
export async function signIn(username,password){
 if(!client)throw Error('O banco ainda não foi conectado.');
 const login=String(username).trim().toLowerCase();
 // Compatibilidade com contas antigas durante a transição; a tela pede usuário.
 if(login.includes('@')){const {error}=await client.auth.signInWithPassword({email:login,password});if(error)throw Error('Usuário ou senha inválidos. Confira seus dados ou consulte o gestor.');return}
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),18000);
 try{
  const response=await fetch(config.url+'/functions/v1/diesel-login',{method:'POST',headers:{'Content-Type':'application/json',apikey:config.publishableKey,Authorization:'Bearer '+(config.loginKey||config.publishableKey)},body:JSON.stringify({username:login,password}),signal:controller.signal});
  const data=await response.json();
  if(!response.ok)throw Error(response.status===429?'Muitas tentativas. Aguarde cinco minutos e tente novamente.':response.status>=500?'Não foi possível conectar. Tente novamente.':'Usuário ou senha inválidos. Confira seus dados ou consulte o gestor.');
  if(!data.access_token||!data.refresh_token)throw Error('Não foi possível entrar. Tente novamente.');
  const {error}=await client.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});
  if(error)throw Error('Não foi possível entrar. Tente novamente.');
 }finally{clearTimeout(timer)}
}
export async function signOut(){await client.auth.signOut({scope:'local'})}
export async function api(path,options={}){
 if(!client)throw Error('O banco ainda não foi conectado.');
 const {data:auth,error:authError}=await client.auth.getSession();if(authError)throw Error('Não foi possível confirmar a conexão. Os registros continuam neste aparelho.');if(!auth.session){const e=Error('Entre com seu usuário e senha.');e.status=401;throw e}
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),18000);
 try{
  if(path==='team-password'){
   const response=await fetch(config.url+'/functions/v1/diesel-login',{method:'POST',headers:{'Content-Type':'application/json',apikey:config.publishableKey,Authorization:'Bearer '+auth.session.access_token},body:JSON.stringify({action:'team-password',...JSON.parse(options.body)}),signal:controller.signal});
   const data=await response.json();if(!response.ok||!data.saved)throw Error(data.error||'Não foi possível salvar a senha.');return data;
  }
  const [route,query]=path.split('?');let rpc,args={};
  if(route==='session')rpc='diesel_session';
  else if(route==='mobile-submit'){rpc='diesel_mobile_submit';args={payload:JSON.parse(options.body)}}
  else if(route==='records'&&options.method==='POST'){rpc='diesel_submit';args={payload:JSON.parse(options.body)}}
  else if(route==='records'){rpc='diesel_records';args={record_id:new URLSearchParams(query).get('id')}}
  else if(route==='admin'&&options.method==='POST'){rpc='diesel_admin_save';args={payload:JSON.parse(options.body)};if(args.payload.action==='import-fleets'){const r=await fetch('./fleets.json');if(!r.ok)throw Error('Catálogo indisponível.');args.payload.fleets=await r.json()}}
  else if(route==='admin')rpc='diesel_admin';
  else throw Error('Operação inválida.');
  const {data,error}=await client.rpc(rpc,args).abortSignal(controller.signal);
  if(error){const e=Error(error.message||'Não foi possível conectar ao banco.');if(error.code==='42501')e.status=403;if(['PGRST301','PGRST302','PGRST303'].includes(error.code))e.status=401;throw e}
  if(data?.error){const e=Error(data.error);e.status=data.status||422;e.data=data;throw e}return data;
 }finally{clearTimeout(timer)}
}

// Campo público: somente catálogo, últimas leituras e inclusão validada no servidor.
export async function fieldApi(route,payload){
 if(!client)throw Error('O banco ainda não foi conectado.');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),10000);
 try{
  const response=await fetch(config.url+'/rest/v1/rpc/'+(route==='session'?'diesel_field_session':'diesel_field_submit'),{method:'POST',headers:{apikey:config.publishableKey,'Content-Type':'application/json'},body:JSON.stringify(route==='session'?{}:{payload}),signal:controller.signal});
  const data=await response.json();
  if(!response.ok){const e=Error('Não foi possível conectar. O registro continua neste aparelho.');e.status=response.status;throw e}
  if(data?.error){const e=Error(data.error);e.status=data.status||422;e.data=data;throw e}return data;
 }finally{clearTimeout(timer)}
}
