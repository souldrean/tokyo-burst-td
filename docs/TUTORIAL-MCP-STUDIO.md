# Tutorial: Claude testando o jogo direto no seu Roblox Studio (MCP)

**O que muda:** hoje eu escrevo o código "às cegas" e você testa. Com o MCP, o Claude roda
no seu PC e consegue **apertar Play, ler o Output, tirar print da tela, clicar e rodar código**
dentro do seu Studio. O erro `FitWithinMaxAxis` da Semana 3 teria sido pego em segundos.

Fonte oficial: https://create.roblox.com/docs/studio/mcp (o MCP agora vem **embutido** no Studio).

⏱️ Tempo total: ~15 min. Faça na ordem.

---

## Passo 1: instalar o Claude no PC (5 min)
1. Baixe o **app Claude para Windows**: https://claude.ai/download
2. Instale e faça login com a sua conta.
3. Dentro do app, abra a aba **Code** (é o Claude Code, o mesmo que estamos usando aqui).

> Se preferir terminal, o Claude Code também tem versão de linha de comando, mas pra começar
> o app é mais fácil.

## Passo 2: trazer o projeto pro PC (3 min)
1. Instale o **GitHub Desktop**: https://desktop.github.com
2. Faça login com a conta **souldrean**.
3. **File → Clone repository** → escolha `souldrean/tokyo-burst-td` → pasta, por exemplo,
   `C:\Users\SEU_USUARIO\Documents\tokyo-burst-td`.

## Passo 3: ligar o MCP no Roblox Studio (2 min)
1. Atualize o Roblox Studio (abra ele; se pedir update, aceite).
2. Abra o painel **Assistant**.
3. Clique em **… → Manage MCP Servers**.
4. Ligue **Enable Studio as MCP server**.

## Passo 4: conectar o Studio ao Claude (2 min)
**Jeito rápido (recomendado):**
1. Ainda no Studio: **Assistant Settings → MCP Servers**.
2. Abra o menu **Quick connect**.
3. Ligue **Claude Code** (e/ou **Claude Desktop**).
   - Se não aparecer na lista: confirme que o Passo 1 foi feito e **reinicie o Studio**.
4. Feche e abra o app Claude de novo.

**Jeito manual (só se o rápido falhar):** no terminal do Windows (PowerShell), com o
Claude Code de linha de comando instalado:
```bash
claude mcp add --transport stdio Roblox_Studio -- cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat
```
> ⚠️ Esse comando eu montei a partir da doc oficial e do exemplo do GitHub da Roblox; não
> consegui testar aqui. Se der erro, me mande o print.

## Passo 5: testar a conexão (3 min)
1. No Studio: abra `build\TokyoBurstTD.rbxlx` (da pasta clonada no Passo 2).
2. No app Claude (aba Code): abra a pasta `tokyo-burst-td` como projeto.
3. Cole esta mensagem:
   ```
   Use o MCP Roblox_Studio: liste os Studios abertos, aperte Play no
   TokyoBurstTD, espere 15 segundos, leia o Output, tire um print da tela
   e pare o Play. Não altere nada no jogo. Me diga se viu algum erro.
   ```
4. ✅ Funcionou se o Claude responder com o Output e uma imagem da tela do jogo.

---

## ⚠️ Regras de segurança (importante)
- O MCP deixa a IA **mexer de verdade** no Studio. Use só nos **seus** jogos.
- Antes de pedir mudanças grandes: **salve** (Ctrl+S) e confirme que o GitHub está atualizado.
- O código "oficial" continua sendo a pasta `src/` no GitHub. O Studio é onde a gente **testa**.
- Não peça pra IA publicar o jogo nem gastar Robux sem você ler o que ela vai fazer.

## ⏭️ Depois disso
Com o Claude rodando no seu PC, o próximo passo é instalar o **Rojo**: o código da pasta `src/`
passa a sincronizar **ao vivo** com o Studio (sem reabrir o `.rbxlx` a cada mudança).
Aqui na nuvem eu fui bloqueado de baixar o Rojo; no seu PC funciona normal.
A gente faz isso junto na primeira sessão local.
