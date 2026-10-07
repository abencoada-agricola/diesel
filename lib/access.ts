import { env } from 'cloudflare:workers';
import { getChatGPTUser } from '../app/chatgpt-auth';
import { defaultRules } from './validation';
export async function access() {
 const user = await getChatGPTUser();
 if (!user) return null;
 const email=user.email.toLowerCase();
 await env.DB!.prepare("INSERT INTO members(email,user_id,role,name) SELECT ?,?,'admin',? WHERE NOT EXISTS (SELECT 1 FROM members)").bind(email,user.userId,user.displayName).run();
 const member = await env.DB!.prepare('SELECT * FROM members WHERE email=?').bind(email).first<any>();
 if (!member || (member.user_id && member.user_id !== user.userId)) return null;
 if (!member.user_id) await env.DB!.prepare('UPDATE members SET user_id=? WHERE email=? AND user_id IS NULL').bind(user.userId,email).run();
 return {...user,displayName:member.name,role:member.role};
}
export async function rules() {const row=await env.DB!.prepare("SELECT value FROM settings WHERE id='rules'").first<any>();return row?{...defaultRules,...JSON.parse(row.value)}:defaultRules;}
export function json(data: any, status=200) {return Response.json(data,{status,headers:{'Cache-Control':'no-store'}});}
