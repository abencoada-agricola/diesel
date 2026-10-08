import {createClient} from './vendor.js';
import {config} from './config.js';
export const isConfigured=()=>/^https:\/\//.test(config.url)&&!!config.publishableKey;
const client=isConfigured()?createClient(config.url,config.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false,storageKey:'diesel-auth'}}):null;
export async function getAuthUserId(){return (await client.auth.getSession()).data.session?.user.id||null}
export async function signIn(email,password){const {error}=await client.auth.signInWithPassword({email,password});if(error)throw Error('E-mail ou senha inválidos. Confira seus dados ou consulte o gestor.')}
export async function signOut(){await client.auth.signOut({scope:'local'})}
export async function api(path,options={}){
 if(!client)throw Error('O banco ainda não foi conectado.');
 const {data:auth}=await client.auth.getSession();if(!auth.session){const e=Error('Entre com seu e-mail e senha.');e.status=401;throw e}
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),18000);
 try{
  const [route,query]=path.split('?');let rpc,args={};
  if(route==='session')rpc='diesel_session';
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
