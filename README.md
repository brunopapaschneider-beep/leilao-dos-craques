# Leilão dos Craques — multiplayer (MVP)

Aplicação web React + Vite + Supabase para duas pessoas jogarem em computadores diferentes, com sala privada por código, lances em tempo real e teto individual privado.

## O que já está preparado
- Autenticação anônima do Supabase.
- Criação de sala privada e entrada por código.
- Limite máximo por participante armazenado no banco.
- Lances incrementais validados no servidor (RPC transacional).
- Atualização em tempo real por Supabase Realtime.
- Registro de elenco arrematado e gastos.
- Interface responsiva para desktop e celular.

## Atenção: etapa de publicação
Este pacote ainda **não está publicado**. Para gerar um endereço público, é necessário conectar uma conta Supabase e uma conta de hospedagem (Cloudflare Pages é uma opção para o front-end). Não compartilhe chaves `service_role` nem senhas.

## 1. Criar o banco Supabase
1. Crie um projeto em https://supabase.com/dashboard.
2. Abra **SQL Editor**.
3. Execute todo o conteúdo de `supabase/schema.sql`.
4. Em Authentication > Providers, habilite **Anonymous Sign-Ins**.
5. Em Project Settings > API, copie Project URL e a chave `anon`/publishable.

## 2. Configurar localmente
```bash
npm install
cp .env.example .env
```
Preencha `.env`:
```env
VITE_SUPABASE_URL=https://SEU-PROJETO.supabase.co
VITE_SUPABASE_ANON_KEY=SUA_CHAVE_PUBLICA_ANON
```
Depois:
```bash
npm run dev
```

## 3. Publicar gratuitamente
1. Envie esta pasta para um repositório GitHub.
2. Crie uma conta em https://pages.cloudflare.com/.
3. Conecte o repositório ao Cloudflare Pages.
4. Build command: `npm run build`
5. Build output directory: `dist`
6. Configure as variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` em Settings > Environment variables.
7. Faça o deploy. O Cloudflare fornecerá um endereço `*.pages.dev`.

## 4. Testar com duas pessoas
1. Abra o site no computador do Bruno e clique em **Entrar no jogo**.
2. Crie uma sala e compartilhe o código com Miguel.
3. Miguel abre o mesmo endereço em outro computador, entra com seu nome e o código.
4. O organizador abre um lote; ambos dão lances ou passam.
5. Cada participante ajusta somente seu próprio limite privado.

## Limitações conhecidas do MVP
- A sala aceita dois participantes.
- A autenticação é anônima e o navegador mantém a sessão local.
- O lote é encerrado quando o participante sem o maior lance passa; se ninguém ofertou, ambos precisam passar para encerrar sem venda. Em produção, recomendamos adicionar relógio de rodada e reconexão robusta.
- O orçamento inicial é individual, mas o controle de teto por jogador e o saldo são validados no servidor.
- A montagem tática dos times e a simulação de partidas serão a próxima etapa após validar o leilão multiplayer.
- O SQL deve ser revisado e testado em um projeto Supabase antes de uso real. Não use dinheiro real: é um jogo recreativo.

## Segurança
A chave `anon` é própria do cliente. Nunca coloque a chave `service_role` no front-end. As operações de lance e limites são executadas por funções SQL `SECURITY DEFINER`, e os limites não são expostos na listagem pública de participantes.
