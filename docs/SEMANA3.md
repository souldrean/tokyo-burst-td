# Semana 3: unidades (torres), dinheiro da partida e efeitos de ataque

## ▶️ Teste agora (5 min)

1. Abra `build/TokyoBurstTD.rbxlx` no Studio e aperte **Play** (F5).
2. Confira:
   - [ ] Embaixo da tela: 3 cartas **Ninja ($50)**, **Samurai ($160)**, **Mage ($260)**
   - [ ] Em cima à direita: seu dinheiro (**$60** no começo)
   - [ ] Toque/clique no **Ninja** → a carta brilha e os quadrados amarelos livres **piscam em ciano**
   - [ ] Toque num quadrado → **explosão de luz** (esfera neon + coluna de luz + anel no chão + confete) e o ninja "nasce" crescendo
   - [ ] O dinheiro desce com flash vermelho
   - [ ] Quando os inimigos chegam perto: **shurikens neon** voando e faísca no acerto
   - [ ] Cada kill: confete + **dinheiro subindo** com animação
   - [ ] Compre um **Samurai** (corte de katana dourado) e um **Mago** (orbe roxo que explode em área, com o orbe flutuando na cabeça dele)
   - [ ] Cartas que você não pode pagar ficam apagadas, com o preço em vermelho
   - [ ] No PC: teclas **1/2/3** escolhem a carta, **Q/Esc** cancelam
3. Meta de dificuldade: posicionando bem, **1 jogador vence** mas sofre nas ondas 8–10.
4. Ao terminar a partida (vitória ou derrota), unidades e dinheiro **zeram** e tudo recomeça.
5. **View → Output** sem erro vermelho. Me manda print se tiver.

## 🧪 Teste de co-op (opcional, 3 min)
No Studio: aba **Test → Clients and Servers → 2 Players → Start**. Abre 2 janelas de jogador.
- Os dois ganham dinheiro a cada kill (regra do co-op)
- Um não consegue colocar torre no slot que o outro já usou ("Slot taken")

## 🧠 O que você aprendeu

### Por que o cliente só "pede" e o servidor "decide"
Quando você toca no quadrado, o cliente manda só: **"quero um Ninja no Slot_03"**.
O servidor confere, nessa ordem:
1. Não está mandando pedido demais (limite de 4 por segundo)
2. Os dados são do tipo certo
3. Essa unidade existe
4. A partida está numa fase que permite colocar
5. O slot existe e está livre
6. Você não passou do limite de 6 unidades
7. Você tem dinheiro

Só aí ele desconta o dinheiro e cria a torre. Mesmo que um hacker mande "Ninja de graça",
o servidor recusa. **É assim que se protege economia em jogo online.**

### Como a torre escolhe quem atacar
10 vezes por segundo o servidor tira uma "foto" de onde todos os inimigos estão, e cada torre
pronta ataca o inimigo **mais adiantado no caminho** dentro do alcance (o mais perigoso).
O Mago também acerta todo mundo num raio em volta do alvo.

### Arquivos novos
| Arquivo | Lado | Faz |
|---|---|---|
| `server/Systems/EconomyService` | Servidor | Dinheiro de cada jogador (só o servidor mexe) |
| `server/Systems/UnitService` | Servidor | Valida a compra, cria a torre, faz o combate |
| `client/Controllers/PlacementController` | Cliente | Cartas, modo de colocar, avisos |
| `client/Controllers/UnitFxController` | Cliente | Torres "vivas": neon pulsando, orbe flutuando, pulo ao atacar |

## 🎯 Desafios (opcional)
1. Em `Shared › Config`, mude `START_CASH` de `60` pra `1000` e monte um exército.
2. Em `UNITS → Ninja`, mude `cooldown` de `0.5` pra `0.1`. Metralhadora de shuriken.
3. Em `UNITS → Mage`, aumente `splashRadius` de `9` pra `25` e veja a explosão gigante.

## ⏭️ Semana 4
**Upgrade e venda** de unidades (tocar na torre abre um painel), nível de cada torre
com visual evoluindo e mais efeito quando ela sobe de nível.
