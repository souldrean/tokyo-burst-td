# Semana 2: ondas de inimigos, vida da base e os primeiros efeitos

## ▶️ Teste agora (5 min)

1. Abra `build/TokyoBurstTD.rbxlx` no Studio e aperte **Play** (F5).
2. Confira:
   - [ ] HUD: "WAVE 0/10", contagem "Next wave in 6" e barra de vida da base
   - [ ] Banner grande **"WAVE 1"** aparece com efeito de "pop"
   - [ ] Demônios (blocos com olhos neon) andam pela estrada balançando
   - [ ] **Clique nos inimigos**: cada clique tira 5 de vida, a barra acima deles desce e eles piscam branco
   - [ ] Quando um inimigo morre: **explosão de confete** colorido + "+5" flutuando
   - [ ] Inimigo que chega na base: **tela treme** + flash vermelho + vida da base desce
   - [ ] Onda 10: banner **"BOSS WAVE!"** e o Oni (grandão com chifres)
   - [ ] Base em 0: "DEFEAT" e a tela fica cinza. Vencer tudo: **chuva de confete "VICTORY!"**
   - [ ] Depois de 8 segundos a partida recomeça sozinha
3. Sem torres ainda, a base cai lá pela **onda 5**. Isso é esperado (as torres chegam na Semana 3).
4. Abre **View → Output**: não pode ter erro vermelho. Se tiver, me manda print.

> O clique nos inimigos só funciona **dentro do Studio**. No jogo publicado ele nem existe
> (o servidor não cria a ferramenta). Isso é segurança: jogador não pode "trapacear" com ela.

## 🧠 O que você aprendeu

### O truque que deixa o jogo leve (a ideia mais importante da semana)
O servidor **não** move os inimigos. Ele só anota em cada um:
`nasceu em tal momento` + `velocidade` + `distância inicial`.
Cada jogador calcula sozinho: **distância = velocidade × tempo que passou**.
- Rede: zero tráfego por frame → roda liso até em celular fraco
- Todo mundo vê o inimigo no mesmo lugar, porque todos usam o mesmo relógio (`GetServerTimeNow`)
- O servidor faz a mesma conta (10 vezes por segundo) pra saber quem chegou na base

### Como o servidor fala com o cliente
| Jeito | Usado pra | Exemplo |
|---|---|---|
| **Atributos** (`MatchState`) | Estado que fica | Onda atual, vida da base |
| **RemoteEvent** servidor → todos | Acontecimento instantâneo | Inimigo morreu (gera o confete) |
| **RemoteEvent** cliente → servidor | Pedido do jogador | Clique de debug (o servidor **confere tudo** antes de aceitar) |

### Arquivos novos
| Arquivo | Lado | Faz |
|---|---|---|
| `server/Systems/MatchService` | Servidor | O "juiz" da partida: espera → ondas → vitória/derrota → recomeça |
| `server/Systems/EnemyService` | Servidor | Cria, machuca e remove inimigos |
| `server/Systems/BaseService` | Servidor | Vida da base |
| `server/Systems/DebugService` | Servidor | Clique de teste (só no Studio, com limite de 10/s) |
| `shared/Net` | Os dois | Cria/acha os RemoteEvents num lugar só |
| `shared/Util/EnemyMath` | Os dois | A conta "distância = velocidade × tempo" |
| `client/Controllers/EnemyRenderer` | Cliente | Move os inimigos na tela + barras de vida |
| `client/Controllers/FxController` | Cliente | **Todo o juice**: confete, números, banners, tremida |
| `tools/sim_match.py` | — | Simula a partida pra calibrar os ~3 minutos |

## 🎯 Desafios (opcional)
1. Em `Shared › Config`, mude `BASE_MAX_HEALTH` de `100` pra `300`. Agora você aguenta mais ondas?
2. No `Config`, ache `ENEMIES` → `Runner` e mude `speed` de `32` pra `60`. Veja os corredores voarem.
3. Mude `DEBUG_HIT_DAMAGE` pra `50` e mate o boss Oni no clique.

## ⏭️ Semana 3
**Torres!** Colocar unidades nos quadrados amarelos, elas atacam sozinhas, e as moedas
de cada kill viram dinheiro da partida pra comprar e melhorar unidades.
