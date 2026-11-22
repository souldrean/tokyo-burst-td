--!strict
-- Clima do mundo: noite em Toquio com neblina roxa e brilho no neon.
-- O servidor muda a Lighting e isso replica para todos os jogadores.
-- Cada efeito tem nome proprio: rodar de novo troca, nao duplica.

local Lighting = game:GetService("Lighting")

local WorldLighting = {}

-- Apaga filhos antigos de uma classe (ex.: a Atmosphere padrao de lugar novo).
-- Duas Atmosphere juntas = o Roblox escolhe uma "aleatoria". Melhor ter so a nossa.
local function removeAll(className: string)
	for _, child in Lighting:GetChildren() do
		if child:IsA(className) then
			child:Destroy()
		end
	end
end

local function removeNamed(name: string)
	local old = Lighting:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

function WorldLighting.apply()
	-- Noite (21h), mas com luz ambiente roxa para crianca no celular ainda enxergar tudo.
	Lighting.ClockTime = 21
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 55, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(115, 95, 155)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.ExposureCompensation = 0.25
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	removeAll("Atmosphere")
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "WorldAtmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(140, 100, 190)
	atmosphere.Decay = Color3.fromRGB(60, 30, 90)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	removeAll("Sky")
	local sky = Instance.new("Sky")
	sky.Name = "WorldSky"
	sky.StarCount = 3000
	sky.Parent = Lighting

	-- Bloom: faz o Neon "vazar" luz. Threshold alto = so o neon brilha, o resto nao.
	removeNamed("WorldBloom")
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "WorldBloom"
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	-- Cores um pouco mais vivas. (O FxController tem o PROPRIO ColorCorrection para flashes.)
	removeNamed("WorldGrade")
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WorldGrade"
	grade.Saturation = 0.15
	grade.Contrast = 0.08
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 240, 255)
	grade.Parent = Lighting

	-- Agua do canal: azul escuro que reflete o neon.
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(20, 40, 80)
	terrain.WaterTransparency = 0.3
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.05
	terrain.WaterWaveSpeed = 4
end

return WorldLighting
