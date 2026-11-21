# Tokyo Burst TD

Tower defense anime no Roblox. Co-op até 4 jogadores, partidas de ~3 minutos,
visual low-poly com neon e efeito em toda ação.

## Como abrir o jogo (sem instalar nada além do Studio)

1. Baixe `build/TokyoBurstTD.rbxlx`.
2. Dê dois cliques nele (ou, no Studio: **File → Open from File**).
3. Aperte **Play** (F5).

## Como gerar o arquivo de novo depois de mudar o código

```bash
python3 -I tools/gen_map.py      # regera o mapa (src/workspace/Map.model.json)
python3 -I tools/build_rbxlx.py  # junta tudo em build/TokyoBurstTD.rbxlx
```

## Estrutura

| Pasta | Vira no Studio | Pra quê |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Config, tipos, matemática pura (cliente e servidor leem) |
| `src/server` | ServerScriptService.Server | Regras do jogo. Só o servidor manda. |
| `src/client` | StarterPlayerScripts.Client | Tela, efeitos, input |
| `src/workspace/Map.model.json` | Workspace.Map | O mapa da cidade |
| `tools/` | — | Scripts Python que geram mapa e o `.rbxlx` |
| `docs/` | — | Specs e explicações de cada semana |

## Caminho profissional (depois)

O projeto já é compatível com [Rojo](https://rojo.space): `rokit install`, `rojo serve`
e o plugin do Rojo no Studio. Lint: `selene src`. Formatação: `stylua src`.
