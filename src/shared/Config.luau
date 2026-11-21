--!strict
-- Config: todos os numeros "ajustaveis" do jogo ficam aqui.
-- Assim, para mudar a velocidade do cubo (por exemplo), voce mexe em UM lugar so.
-- table.freeze deixa a tabela somente leitura: ninguem muda um valor por engano.

local Config = {
	-- Liga/desliga o cubo de teste que anda pelo caminho dos inimigos.
	PATH_PREVIEW_ENABLED = true,
	-- Velocidade do cubo em studs por segundo.
	PATH_PREVIEW_SPEED = 20,
	-- Tamanho do cubo (3x3x3 studs).
	PATH_PREVIEW_CUBE_SIZE = 3,
	-- Altura (Y) onde o cubo anda. A estrada fica perto de Y = 0.
	PATH_PREVIEW_HEIGHT = 2,
}

return table.freeze(Config)
