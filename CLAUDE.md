# Tokyo Burst TD — guia do projeto para o Claude

## Dono e jeito de falar
- Dono: João, 18 anos, iniciante em Roblox/Luau (vem de Google Apps Script). Objetivo: aprender + portfólio.
- Responda em **português**, direto, como sócio/mentor. Comece pelo que ele precisa fazer agora.
- Sinalize as etapas ("Etapa 1/4: ..."). Se faltar informação, **pergunte** antes de supor.
- Seja honesto sobre o que não foi testado.

## Protocolo ecc@ecc (quando ele digitar `ecc`)
1. Carregar as skills `roblox-dev` relevantes (architecture, security, ui, performance, luau-strict-typing, datastores, testing).
2. Você é o **orquestrador**: escreve um spec com contratos exatos em `docs/SPEC-SEMANA<N>.md`.
3. Dispara **executores em paralelo** (subagentes, outro modelo), cada um dono de arquivos diferentes.
4. Dispara **revisores** em paralelo (`roblox-dev:roblox-reviewer` + um revisor de contrato servidor↔cliente).
5. Aplica correções, builda, **testa no Studio via MCP**, commita e faz push.
6. Entrega um `docs/SEMANA<N>.md` com checklist de teste + o que ele aprendeu.

## O jogo
Tower defense anime (personagens **originais**, nunca copiar animes/jogos existentes), co-op até 4,
partidas de ~3 min, low-poly + neon, **juice em toda ação** (confete, luz, pop). Público 10–18,
mobile + PC, UI em inglês. Sem monetização na v1.

Plano: S1 mapa ✅ · S2 ondas/inimigos/base ✅ · S3 unidades + dinheiro ✅ (aguardando teste das cartas) ·
S4 upgrade/venda · S5 juice extra · S6 DataStore · S7 gacha + pity · S8 lobby/co-op teleporte ·
S9 level/missões diárias · S10 UI mobile + arte · S11 QA/perf · S12 lançamento.

## Estrutura (Rojo)
| Pasta | No Studio |
|---|---|
| `src/shared` | ReplicatedStorage.Shared (Config, Types, Net, Util/PathMath, Util/EnemyMath) |
| `src/server` | ServerScriptService.Server (único Script) + `Systems/` ModuleScripts |
| `src/client` | StarterPlayerScripts.Client (único LocalScript) + `Controllers/` ModuleScripts |
| `src/workspace/Map.model.json` | Workspace.Map (gerado por `tools/gen_map.py`) |

Regras de código: `--!strict` em todo arquivo, tabs, identificadores em inglês, **comentários em
português simples** explicando o porquê. Módulos com `init()` (sem yield) e `start()`. Nada de `_G`.
Servidor decide tudo; cliente só renderiza e pede. Valide todo argumento de remote.
Contratos atuais: ver `docs/SPEC-SEMANA1..3.md`.

## Build e teste
```bash
python3 tools/gen_map.py       # regera o mapa
python3 tools/build_rbxlx.py   # gera build/TokyoBurstTD.rbxlx (sem precisar de Rojo)
python3 tools/sim_match.py     # balanceamento (manter em sync com Config.luau)
```
- **Sempre teste no Studio pelo MCP `Roblox_Studio`** antes de dizer que funciona:
  `get_studio_state` → `start_stop_play` → esperar → `get_console_output` → `screen_capture` → parar.
  Erros de API (ex.: enum inexistente) só aparecem assim — revisão por leitura já deixou passar um.
- Não publique o jogo, não gaste Robux, não insira assets da loja sem o João aprovar.

## Primeira sessão local (pendente)
1. Confirmar que o MCP conecta (teste do `docs/TUTORIAL-MCP-STUDIO.md`, passo 5).
2. Instalar **Rokit** e rodar `rokit install` (Rojo, Selene, StyLua pinados em `rokit.toml`),
   instalar o plugin do Rojo no Studio, usar `rojo serve` para sync ao vivo.
3. Rodar `selene src` e corrigir avisos.
4. Confirmar que as 3 cartas da hotbar aparecem (bug `FitWithinMaxAxis` corrigido no commit d730b69).

## Git
Commits pequenos em português, `git push` ao terminar cada etapa. Nunca commitar segredos.
