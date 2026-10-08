// Credenciais administrativas existem somente no ambiente da função.
const url = Deno.env.get('SUPABASE_URL')!;
const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const publicKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const allowedOrigins = new Set(['https://abencoada-agricola.github.io','https://localhost']);
Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || '';
  const headers = {'Content-Type':'application/json', 'Cache-Control':'no-store', 'Vary':'Origin',
    'Access-Control-Allow-Origin':allowedOrigins.has(origin) ? origin : 'https://abencoada-agricola.github.io',
    'Access-Control-Allow-Headers':'content-type,apikey,authorization', 'Access-Control-Allow-Methods':'POST, OPTIONS'};
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status,headers});
  if (origin && !allowedOrigins.has(origin)) return reply({error:'Acesso inválido.'},403);
  if (req.method === 'OPTIONS') return new Response(null,{status:204,headers});
  if (req.method !== 'POST') return reply({error:'Método inválido.'},405);
  const invalid = () => reply({error:'Usuário ou senha inválidos.'},401);
  try {
    if (Number(req.headers.get('content-length')) > 4096) return invalid();
    const text = await req.text();
    if (text.length > 4096) return invalid();
    const body = JSON.parse(text);
    if (typeof body.username !== 'string' || typeof body.password !== 'string' || !body.password || body.password.length>1024) return invalid();
    const username = body.username.trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9_.-]{2,29}$/.test(username)) return invalid();
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
    const targetResponse = await fetch(url+'/rest/v1/rpc/diesel_login_target', {
      method:'POST',headers:{apikey:secret,Authorization:'Bearer '+secret,'Content-Type':'application/json'},
      body:JSON.stringify({login_name:username,request_ip:ip}),signal:AbortSignal.timeout(10000)});
    if (!targetResponse.ok) return reply({error:'Serviço indisponível.'},503);
    const target = await targetResponse.json();
    if (target.status === 429) return reply({error:'Aguarde cinco minutos.'},429);
    // Desconhecidos também passam pelo Auth: mesma resposta, sem lista de contas.
    const authResponse = await fetch(url+'/auth/v1/token?grant_type=password', {
      method:'POST',headers:{apikey:publicKey,'Content-Type':'application/json'},
      body:JSON.stringify({email:target.email || 'inexistente@usuarios.invalid',password:body.password}),signal:AbortSignal.timeout(10000)});
    if (authResponse.status === 429) return reply({error:'Aguarde cinco minutos.'},429);
    if (!authResponse.ok || !target.email) return invalid();
    const session = await authResponse.json();
    return reply({access_token:session.access_token,refresh_token:session.refresh_token});
  } catch { return reply({error:'Não foi possível entrar. Tente novamente.'},503); }
});
