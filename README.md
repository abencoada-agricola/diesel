# Abençoada — Controle de diesel

Aplicação web instalável (PWA) para Android e desktop. Interface em `public/campo.html`, APIs autenticadas em `app/api`, banco compartilhado Cloudflare D1.

## Funcionalidades
- Cadastro com data, frota, horímetros de motor/elevador, KM, início/final do registro e litros obrigatórios.
- Assinatura automática: nome cadastrado da conta autenticada, confirmada no servidor; o cliente não pode substituir a identidade.
- IndexedDB guarda rascunho e fila por usuário; Service Worker guarda a interface para abrir offline.
- Sincronização a cada 15 segundos com a aplicação aberta, ao voltar a conexão e por botão. A fila só é removida após confirmação. Identificadores únicos evitam duplicação por tentativas repetidas.
- KM e horímetros inferiores a qualquer leitura confirmada da frota são bloqueados com validação atômica no banco. Valores iguais são permitidos. No aparelho a conferência usa os valores já conhecidos, incluindo pendentes; no servidor usa todos os recebidos.
- Divergências ficam na fila com aviso e botão de correção. Nunca são enviadas como confirmadas.
- Gestor cadastra frotas e e-mails permitidos; operador consulta seus próprios registros. Todas as APIs conferem identidade e perfil.
- Histórico por frota, avisos de novos registros enquanto o painel está aberto, CSV compatível com Excel e impressão em formato da ficha.

## Uso inicial e acesso à equipe
A publicação começa **privada para o proprietário**. O primeiro usuário autenticado nessa publicação recebe o perfil de gestor. Antes de ampliar o acesso, o proprietário deve abrir o sistema e inicializar sua conta. Depois cadastre frotas reais e os membros da equipe em Configurações. O acesso da publicação precisa ser compartilhado pela plataforma Sites; cadastrar um e-mail dentro do sistema não libera sozinho o acesso à publicação. A autenticação usa a conta ChatGPT autorizada pela plataforma, não senha interna.

Antes de ir para o campo, cada trabalhador deve abrir com internet, entrar e aguardar o preparo do modo offline. No Chrome Android, usar Instalar aplicativo/Adicionar à tela inicial. Voltar a abrir o app com conexão para sincronizar. A primeira entrada em um aparelho novo exige internet.

## Limites operacionais
- O aplicativo não envia notificações push ou WhatsApp com o painel fechado. Avisos no sino e notificações opcionais do navegador dependem do painel em execução.
- Dados offline ficam no navegador do aparelho. Não limpar armazenamento, desinstalar ou trocar de aparelho com registros pendentes. A persistência solicitada ao navegador é uma proteção adicional, não substitui cópia no servidor.
- Aparelhos compartilhados guardam dados offline de contas já usadas; recomenda-se aparelho pessoal ou perfil de navegador separado. A consulta no servidor permanece protegida por perfil.
- Regras alteradas pelo gestor são atualizadas com conexão. A validação no servidor usa as regras vigentes no recebimento.
- Início/final são números, conforme referência. Litros igual à diferença só é exigido quando essa opção está ativada. Horários de recebimento são UTC internamente; a interface usa o horário do dispositivo.
- Registros confirmados são preservados sem edição/exclusão. Correção de leitura só para registros rejeitados na fila.

## Desenvolvimento
Node >=22.13.0. `npm run dev` inicia http://127.0.0.1:5173; entrada local simulada `/signin-with-chatgpt?return_to=/campo.html`. Identidade de teste `Seedy`. Esse simulador não vai para produção.

`npm run db:generate` gera migrações do schema. Aplicar localmente com Wrangler, segundo README do starter. `npx tsc --noEmit`, `node --check public/ui-v3.js` e `node tests/api.mjs` verificam tipos, sintaxe e regras essenciais. O teste API precisa do servidor local com migração aplicada e base de teste sem leituras prévias de QA-01; cria apenas dados locais. Não executar contra produção.

O deploy Sites aplica as migrações e provisiona D1. A origem da publicação está registrada em `.openai/hosting.json`.

## Telas separadas
`/campo` é a entrada mobile com somente o formulário obrigatório, assinatura da conta, envio e status de pendências. `/admin` exige perfil gestor no servidor e contém o painel de registros, frotas, equipe e avisos. Ambos usam o mesmo banco e a mesma fila offline. A raiz e a instalação Android abrem `/campo`.

## Catálogo Gmais
246 frotas da listagem ativa exportada em 07/10/2026. O botão Importar frotas Gmais no painel aplica o catálogo sem apagar registros. Apenas códigos, modelos e tipos foram incluídos; a planilha original não integra este repositório. Leituras não foram importadas porque a coluna de hodômetro não distingue KM de horas.

## GitHub Pages
Hospedagem solicitada: GitHub Pages. A tentativa de ativação retornou HTTP 422: o plano atual não suporta Pages neste repositório privado. O repositório foi mantido privado.

Este código completo usa servidor Cloudflare D1 e identidade fornecida pelo Sites. GitHub Pages serve somente arquivos estáticos e não executa as APIs deste projeto. Para a migração, além de habilitar Pages, é necessário hospedar a API/banco separadamente, configurar uma autenticação apropriada e adaptar a interface para a origem externa e o prefixo /diesel/. Não publicar a pasta public isoladamente como um sistema completo: registros não seriam recebidos pelo servidor.

Publicação funcional atual: https://abencoada-diesel.mateusfrmacedo.chatgpt.site/campo
Administração: https://abencoada-diesel.mateusfrmacedo.chatgpt.site/admin
