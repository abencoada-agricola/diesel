import {build} from 'esbuild';
import {cp,rm,mkdir,writeFile,readFile,rename} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const url=process.env.SUPABASE_URL||'',key=process.env.SUPABASE_PUBLISHABLE_KEY||'';
if(key.startsWith('sb_secret_'))throw Error('Use a chave pública publishable, nunca uma chave secret.');
if(key.includes('.')){try{if(JSON.parse(Buffer.from(key.split('.')[1],'base64url')).role==='service_role')throw Error('A chave service_role não pode ser publicada.')}catch(e){if(e.message.includes('service_role'))throw e}}
await build({stdin:{contents:"export {createClient} from '@supabase/supabase-js'",resolveDir:process.cwd()},bundle:true,format:'esm',platform:'browser',target:'es2022',outfile:'web/vendor.js',minify:true});
await rm('dist',{recursive:true,force:true});await mkdir('dist');await cp('web','dist',{recursive:true});
if(url&&key)await writeFile('dist/config.js',`export const config=${JSON.stringify({url,publishableKey:key})};\n`);
const names=['app.js','backend.js','config.js','vendor.js','style.css'];const hash=createHash('sha256');for(const name of [...names,'index.html','admin.html','sw.js'])hash.update(await readFile('dist/'+name));const version=hash.digest('hex').slice(0,12);
const renamed=Object.fromEntries(names.map(name=>[name,name.replace(/\.(js|css)$/,'-'+version+'.$1')]));
for(const name of ['index.html','admin.html','app.js','backend.js','sw.js']){let content=await readFile('dist/'+name,'utf8');for(const [from,to] of Object.entries(renamed))content=content.replaceAll('./'+from,'./'+to);content=content.replaceAll('diesel-pages-v1','diesel-pages-'+version);await writeFile('dist/'+name,content)}
for(const [from,to] of Object.entries(renamed))await rename('dist/'+from,'dist/'+to);
await writeFile('dist/.nojekyll','');
console.log(url&&key?'Interface pronta para publicar com banco conectado.':'Interface pronta; conexão do banco pendente.');
