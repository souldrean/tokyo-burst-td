--!strict
-- HudController: cria o HUD (interface) simples: titulo e etiqueta de versao.
-- Tudo em Scale (porcentagem da tela) para funcionar em celular e PC.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PINK = Color3.fromRGB(255, 51, 153)
local CYAN = Color3.fromRGB(0, 240, 255)

local HudController = {}

function HudController.init() end

function HudController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false -- nao some quando o personagem morre
	gui.IgnoreGuiInset = false -- respeita a barra superior do Roblox
	gui.Parent = playerGui

	-- Titulo no topo, centro da tela.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.01)
	title.Size = UDim2.fromScale(0.45, 0.07)
	title.BackgroundTransparency = 1
	title.Text = "TOKYO BURST TD"
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true -- o texto se ajusta ao tamanho da caixa
	title.TextColor3 = CYAN
	title.Parent = gui

	-- Limites: o texto nao fica minusculo no celular nem gigante no PC.
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MinTextSize = 14
	sizeLimit.MaxTextSize = 52
	sizeLimit.Parent = title

	local stroke = Instance.new("UIStroke")
	stroke.Color = PINK
	stroke.Thickness = 2
	stroke.Parent = title

	-- Pulso: um Tween so, repetindo para sempre e voltando (reverses = true).
	-- Bem mais leve do que mexer no texto a cada frame.
	local pulseInfo = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stroke, pulseInfo, { Thickness = 4, Color = CYAN }):Play()
	TweenService:Create(title, pulseInfo, { TextColor3 = PINK }):Play()

	-- Etiqueta pequena logo abaixo do titulo (longe dos controles do celular).
	local tag = Instance.new("TextLabel")
	tag.Name = "BuildTag"
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.fromScale(0.5, 0.09)
	tag.Size = UDim2.fromScale(0.25, 0.05)
	tag.BackgroundTransparency = 1
	tag.Text = "Week 1 build"
	tag.Font = Enum.Font.GothamBold
	tag.TextScaled = true
	tag.TextColor3 = Color3.fromRGB(200, 215, 255)
	tag.TextTransparency = 0.2
	tag.Parent = gui

	local tagLimit = Instance.new("UITextSizeConstraint")
	tagLimit.MinTextSize = 12
	tagLimit.MaxTextSize = 20
	tagLimit.Parent = tag
end

return HudController
