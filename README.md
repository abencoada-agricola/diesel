# Abençoada — Diesel

Sistema web instalável para Android, publicado pelo GitHub Pages. Login próprio com nome de usuário e senha, autenticação e banco PostgreSQL no Supabase. A interface funciona no Pages; registros são recebidos pelo banco conectado.

## Endereços

- Campo: https://abencoada-agricola.github.io/diesel/
- Administração: https://abencoada-agricola.github.io/diesel/admin.html

## Conectar o banco

1. Crie um projeto Supabase no plano escolhido.
2. Execute `supabase/schema.sql` uma vez no SQL Editor, depois `supabase/fleets.sql`. Após cadastrar o gestor, execute `supabase/usernames.sql` uma vez e publique a função `supabase/functions/diesel-login/index.ts` com o nome `diesel-login`, conforme `supabase/config.toml`. O catálogo tem 246 frotas ativas exportadas do Gmais em 07/10/2026, contendo somente código, modelo e tipo.
3. Em Authentication, desative o cadastro público e crie a conta do gestor com e-mail e senha. Não informe senhas no código.
4. No SQL Editor, cadastre esse mesmo e-mail: `insert into public.members(email,name,role) values('seu-email-em-minusculas','Seu nome','admin');`. O primeiro visitante não recebe automaticamente o perfil de gestor.
5. No repositório, Settings → Secrets and variables → Actions → Variables: defina `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`. Use a chave pública publishable ou anon. Nunca use service_role ou secret na interface.
6. Execute o workflow **Publicar sistema**. Sem essas variáveis, a interface informa que o sistema está em configuração e bloqueia o uso.
7. Crie as contas dos trabalhadores em Authentication. Cadastre os mesmos e-mails, nomes e um usuário único na administração do sistema. Operadores só consultam seus registros; gestores consultam a operação.

A conta e a senha são administradas no Supabase. A tela do sistema permite autorizar usuários existentes e escolher o perfil, sem expor chaves administrativas no navegador.

## Uso no campo

Abra com internet, entre com sua conta e aguarde o carregamento inicial e confira a abertura sem internet antes de sair para o campo. Instale pelo menu do Chrome no Android. Rascunhos e registros pendentes são guardados no IndexedDB, por usuário. Ao voltar a conexão, abra o aplicativo para sincronizar. A fila só é removida depois da confirmação do banco; uma identificação única impede registros duplicados.

Data e hora são registradas automaticamente ao enviar. Frota, horímetros do motor/elevador, KM, início/final e litros são obrigatórios. Litros devem ser positivos e final deve superar início. Valores de KM e horímetros não podem ser menores que nenhuma leitura já recebida da mesma frota. A conferência é feita no celular e no banco. Uma trava na frota serializa os envios simultâneos. Leituras iguais são aceitas. Registros divergentes ficam para correção.

A assinatura é o nome autorizado da conta autenticada e é definida pelo banco. O navegador não pode alterá-la. Registros confirmados são preservados sem edição ou exclusão. As funções verificam autorização e perfil; tabelas têm RLS e não concedem acesso direto aos clientes.

O painel consulta novos registros a cada 15 segundos quando aberto, apresenta avisos e permite exportar CSV ou imprimir por frota. Notificações com o painel fechado não estão implementadas. Não limpe os dados do navegador com registros pendentes. Trocar de aparelho não transfere a fila local.

## Desenvolvimento

Node 22+. `npm ci`, `npm test`, `npm run build`. `npm run dev` abre a interface local. O build gera `dist/` e inclui o SDK de autenticação nos arquivos offline, sem dependência de CDN em campo. O workflow publica somente `dist/`, respeitando o prefixo `/diesel/`.

Os testes executam o schema PostgreSQL em PGlite e verificam o catálogo, campos obrigatórios, leituras inferiores, valores iguais, assinatura, idempotência e permissões de operador, gestor e visitante. Testes não acessam o banco de produção.

Chaves públicas de configuração podem ser incluídas no build; a segurança dos dados depende das permissões e funções do banco. Senhas, chaves administrativas e tokens pessoais não devem integrar o repositório.

## Login por usuário

O usuário tem 3 a 30 letras sem acentos, números, pontos, traços ou sublinhados; maiúsculas e minúsculas são equivalentes. A migração sugere o prefixo do e-mail para contas existentes. O gestor pode alterar em Configurações → Equipe e acessos → Editar usuário. A senha e a identidade da conta permanecem as mesmas. O e-mail ainda é aceito durante a transição.

A função de entrada resolve o nome no servidor, valida a senha pelo Supabase Auth e retorna somente os tokens da sessão. A chave administrativa usa o ambiente automático da Edge Function e nunca vai ao Pages. O tradutor de nomes só pode ser chamado por service_role; visitantes e operadores não podem consultar e-mails. As tentativas são limitadas por usuário e IP em janelas de cinco minutos. Deploy pelo editor Supabase ou `supabase functions deploy diesel-login`; mantenha verify_jwt=true e defina a variável pública SUPABASE_LOGIN_KEY com a chave anon JWT para essa função de entrada. Ela exige senha válida e nunca recebe service_role do navegador. Não registre corpo de requisições ou senhas em logs.
