# Semana 1: esqueleto + mapa cinza + caminho funcionando

## ▶️ Teste agora (5 min)

1. Baixe `build/TokyoBurstTD.rbxlx` e abra no Roblox Studio (**File → Open from File**).
2. Aperte **Play** (F5).
3. Confira:
   - [ ] Cidade cinza com estrada escura em zigue-zague
   - [ ] Pad vermelho neon (início) e bloco azul neon (sua base, no fim)
   - [ ] 10 quadrados amarelos transparentes do lado da estrada (onde as unidades vão ficar)
   - [ ] **Cubo rosa andando pela estrada em loop** ← prova que o caminho funciona
   - [ ] Título "TOKYO BURST TD" piscando em neon no topo
4. Abra a janela **Output** (View → Output) e veja:
   `[Server] ...` sem erro vermelho.
5. Checagem extra (2 coisas que não deu pra confirmar sem Studio): na **barra de comando** (View → Command Bar), cole e aperte Enter:
   ```lua
   print(Enum.Material.Asphalt.Value, Enum.Material.Concrete.Value)
   ```
   Tem que aparecer `1376 816`. Me manda print se der diferente, ou se alguma peça vier com tamanho errado.

## 🧠 O que você aprendeu (lê com o Studio aberto)

### Servidor vs Cliente: a regra mais importante do Roblox
- **Servidor** (ServerScriptService): o "juiz". Decide tudo que importa: vida, moedas, onde o inimigo está.
- **Cliente** (StarterPlayerScripts): a "TV" de cada jogador. Só mostra tela e efeitos.
- Hacker consegue mexer no cliente, mas **nunca** no servidor. Por isso regra de jogo vai sempre no servidor.

### Onde cada coisa está no Studio

| No Studio | Arquivo | O que faz |
|---|---|---|
| ReplicatedStorage › Shared › Config | `src/shared/Config.luau` | Números ajustáveis (velocidade do cubo etc.). Mude aqui e teste! |
| Shared › Util › PathMath | `src/shared/Util/PathMath.luau` | Matemática pura: "andei X studs, onde estou no caminho?" |
| ServerScriptService › Server | `src/server/init.server.luau` | O **único** Script do servidor. Liga todos os sistemas em 2 fases. |
| Server › Systems › PathService | `.../PathService.luau` | Lê os waypoints 1→8 do mapa e confere se estão certos |
| Server › Systems › PathPreview | `.../PathPreview.luau` | O cubo rosa de teste |
| StarterPlayerScripts › Client | `src/client/init.client.luau` | O **único** LocalScript. Liga os controllers. |
| Client › Controllers › HudController | `.../HudController.luau` | Título neon na tela |
| Workspace › Map | `src/workspace/Map.model.json` | O mapa (gerado por `tools/gen_map.py`) |

### Por que "init" e "start" (duas fases)?
Primeiro **todos** os sistemas se preparam (`init`), depois **todos** começam a rodar (`start`).
Assim nenhum sistema tenta usar outro que ainda não está pronto. Isso evita um dos bugs mais comuns de iniciante.

### Por que ModuleScript em vez de vários Scripts?
Vários Scripts soltos rodam em ordem aleatória e viram bagunça. Com 1 Script e vários
ModuleScripts, você controla tudo. É assim que jogos grandes fazem.

## 🎯 Desafio (opcional, 10 min)
1. Em `Config`, mude `PATH_PREVIEW_SPEED` de `20` pra `60` e aperte Play. O cubo corre mais?
2. No Explorer, abra Workspace › Map › Waypoints, selecione a peça `4` e arraste ela. Aperte Play. O cubo segue o novo caminho?

Se os dois funcionarem, você entendeu a base do TD.

## ⏭️ Semana 2
Inimigos de verdade saindo em ondas, andando pelo caminho e tirando vida da base.
