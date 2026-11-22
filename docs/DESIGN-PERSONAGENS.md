# Tokyo Burst TD — Fichas dos personagens (aprovadas pelo João em 2026-11-22)

Todos os personagens são **originais**. Os nomes foram checados por busca contra personagens
famosos do mesmo tipo (ex.: "Kaze" foi descartado porque já existe um ninja famoso com esse nome).
O nome aparece como **"Nome • Classe"**. No nível 4 vira **"Nome • Evolução"**
(ex.: "Sumi • Shadow Ninja"). As evoluções aprovadas na Semana 4 continuam iguais.

## Estilo visual (vale para todos)
- **Chibi low-poly**: cabeça grande (≈40% da altura), corpo curto, braços e pernas de bloco.
  Um "gancho de silhueta" por personagem, para reconhecer de longe e de cima.
- **Neon só nos detalhes** (faixa, arma, olhos). O corpo usa cores **médias/claras**, porque o
  mundo agora é noturno e corpo escuro some no chão.
- **Limite por personagem**: 15–20 peças, sem PointLight, sombra só no corpo. Podem existir 24
  unidades na tela, além das 576 peças do mundo.
- **Evolução (nível 4)**: além da cor nova, aparecem **peças extras** (capa, segunda arma, aura).
  Elas já vêm no modelo, escondidas, e aparecem quando o nível chega a 4.

## Iniciais (já jogáveis — ganham modelo novo e nome)
| Personagem | Papel | Paleta | Gancho de silhueta | Evolução (nv 4) |
|---|---|---|---|---|
| **Sumi • Ninja** | Rápido, alvo único | Azul-marinho claro + ciano | Cachecol longo esvoaçando, máscara, 2 shurikens nas costas | **Shadow Ninja** (roxo): capa rasgada + 2ª lâmina. MultiShot 3 |
| **Tetsu • Samurai** | Dano pesado, curto alcance | Vermelho-armadura + dourado | Chapéu largo de palha, ombreiras grandes, katana na cintura | **Storm Samurai** (azul-raio): chifres de raio no elmo + 2ª katana. Crit a cada 3 golpes, 3x |
| **Mirai • Mage** | Dano em área | Lilás + rosa neon | Chapéu cônico alto e torto, cajado com orbe | **Frost Archmage** (gelo): coroa de cristais + orbe vira cristal. Slow 40% por 2s |

## Novos (para o gacha da S7 — só modelo e ficha agora, NÃO jogáveis ainda)
Por que ainda não jogáveis: o servidor aceita qualquer unidade que esteja em `Config.UNITS`. Se
colocarmos agora, qualquer jogador (ou exploiter) usaria de graça. Eles entram no jogo junto com o
gacha/inventário da S7, com um spec próprio.

| Personagem | Raridade | Papel | Paleta | Gancho de silhueta | Habilidade da evolução |
|---|---|---|---|---|---|
| **Hoshi • Neon Archer** | Comum | Alcance muito longo, alvo único | Branco + amarelo neon | Arco grande de neon, rabo de cavalo alto, visor | **Starfall Archer**: Crit a cada 4 tiros, 2.5x (*reusa Crit*) |
| **Jiro • Street Brawler** | Raro | Curto alcance, onda de choque em área | Laranja + verde-limão | Luvas gigantes, jaqueta aberta, cabelo espetado | **Thunder Brawler**: Slow 50% por 1s, um "quase atordoar" (*reusa Slow*) |
| **Kohana • Fox Spirit** | Épico | Ataques rápidos em vários alvos | Branco + rosa-sakura | Orelhas de raposa, 3 caudas, máscara de festival na lateral | **Moonfire Fox**: 4 fogos-fátuos de uma vez (*reusa MultiShot*) |
| **Volt • Mecha Pilot** | Lendário | Área grande, lento | Cinza-metal + ciano elétrico | Pequeno piloto dentro de um mini-mecha com canhões nos ombros | **Giga Mech**: 3 mísseis em alvos diferentes (*reusa MultiShot*; falta conferir se MultiShot aplica splash) |

Números de partida (só esboço; o ajuste fino vem no spec da S7 com o `sim_match.py`):
| | Custo | Dano | Alcance | Recarga | Splash |
|---|---|---|---|---|---|
| Hoshi | 90 | 10 | 36 | 0.9 | 0 |
| Jiro | 140 | 22 | 14 | 1.0 | 6 |
| Kohana | 220 | 9 | 26 | 0.6 | 0 |
| Volt | 380 | 26 | 30 | 1.6 | 10 |

As 4 habilidades **reusam** os tipos que já existem (MultiShot/Crit/Slow), então não precisa de
mecânica nova no servidor. Ideia para o futuro: uma "Idol" de suporte que dá buff de dano aos
vizinhos (essa seria mecânica nova).

## Como vai ser construído (contrato técnico)
- Arquivo novo `src/server/Units/UnitModels.luau` com a função
  `build(id, kind, def, baseCFrame) -> (Model, BasePart)`. Mesma assinatura do `buildModel` atual.
- O contrato de hoje continua valendo: `model.Name = id`, `PrimaryPart = Root` (ancorado), o `Hitbox`
  é a ÚNICA peça com `CanQuery` e tem o tamanho de `def.height`, a frente é −Z, os nomes de `kind`
  não mudam e as peças de destaque usam `Material.Neon` (o UnitFxController colore essas peças
  por nível).
- `UnitModels.setLevel(model, level)` mostra as peças de evolução no nível 4.
- Integração com o jogo, que mexe em arquivos de outra sessão e por isso precisa de combinação:
  1 linha no `UnitService` (trocar `buildModel` por `UnitModels.build`), 1 linha no upgrade
  (`UnitModels.setLevel`) e o `displayName` com nome próprio no `Config`.
- Primeiro passo: uma **vitrine no Studio** (os 7 lado a lado, + as 3 evoluções) para você aprovar
  o visual antes de ligar no jogo.
