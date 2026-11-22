# Semana 4: upgrade (até o nível 4 + evolução) e venda

## ▶️ Teste agora (5 min)

1. Abra o Studio, conecte o Rojo (Plugins → Rojo → Connect → **Accept**) e aperte **Play** (F5).
2. Confira:
   - [ ] Coloque um Ninja e **clique/toque nele** → abre o painel com nome, nível, DMG/RANGE/SPEED
   - [ ] **Upgrade** (ou tecla **E**) → o nível sobe, o brilho fica mais forte, estrelinhas em cima da unidade
   - [ ] No **nível 4** a unidade **evolui**: nome novo, cor nova e caixa "ABILITY"
     - Ninja → **Shadow Ninja** (acerta 3 inimigos de uma vez)
     - Samurai → **Storm Samurai** (golpe crítico de tempos em tempos)
     - Mage → **Frost Archmage** (deixa os inimigos mais lentos)
   - [ ] No nível 4 o botão vira **MAX**
   - [ ] **Sell**: durante a onda devolve **60%**; no intervalo entre ondas devolve **100%**
   - [ ] **Backspace** vende só se apertar **duas vezes** ("Press again")
   - [ ] **Esc**, **Q**, o **X** ou tocar no chão vazio fecham o painel
   - [ ] Quando uma onda é limpa: pausa de **5 s** ("Next wave in N")
   - [ ] Quando a partida acaba, o painel fecha sozinho
   - [ ] Aviso "Not enough cash!" aparece no **topo** (não fica atrás do painel)
3. **View → Output** sem erro vermelho.

## ✅ O que o Claude já testou no Studio (via MCP)
- Teste puro `UnitMath.spec`: **145 passaram, 0 falharam**.
- Upgrade 1→2→3→4 cobra o preço certo; um 5º upgrade é recusado.
- Vender na onda devolveu exatamente 60% (350 → 210). Vender **duas vezes** a mesma unidade e mandar
  dados lixo (id numérico, texto de 5000 letras) foi ignorado sem erro.
- Painel do Frost Archmage abriu com clique: "Sell $648" (= 60% de 1080) ✔
- Console sem erro do nosso código.

Não testado: celular de verdade, co-op com 2 jogadores, o equilíbrio das ondas 8–10.

## 🧠 O que você aprendeu

### Dinheiro não duplica nem com clique duplo
Na venda o servidor **primeiro apaga a unidade** e **depois** devolve o dinheiro. Se um hacker
mandar "vender" 10 vezes, da 2ª em diante a unidade já não existe → nada acontece.
A ordem das linhas é a defesa.

### Matemática pura = dá para testar sem jogar
`UnitMath` só recebe números e devolve números (não mexe em peças nem remotes). Por isso dá
para rodar 145 testes em 1 segundo. Servidor e cliente usam o **mesmo** arquivo, então o preço
que o painel mostra é sempre o preço que o servidor cobra.

### Revisores pegam o que você não vê
Dois revisores leram o código. Acharam: botão Upgrade ativo com a partida acabada, painel
cobrindo o aviso de dinheiro, Esc que não fechava, e um clique que fazia duas coisas. Tudo
corrigido antes do teste.
