--!strict
-- Net: acesso centralizado aos RemoteEvents.
-- No servidor: cria a pasta ReplicatedStorage.Remotes e cada evento sob demanda
-- (assim a ordem de init() entre sistemas nao importa).
-- No cliente: so espera o evento existir (cliente nunca cria remotes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

export type RemoteName = Types.RemoteName

local FOLDER_NAME = "Remotes"
local CLIENT_TIMEOUT = 30

local Net = {}

local function getServerFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		assert(existing:IsA("Folder"), "Net: ReplicatedStorage.Remotes deveria ser uma Folder")
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

function Net.event(name: RemoteName): RemoteEvent
	if RunService:IsServer() then
		local folder = getServerFolder()
		local existing = folder:FindFirstChild(name)
		if existing then
			assert(existing:IsA("RemoteEvent"), `Net: "{name}" deveria ser um RemoteEvent`)
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	-- Cliente: espera com tempo limite e erro claro.
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, CLIENT_TIMEOUT)
	assert(folder, `Net: ReplicatedStorage.Remotes nao apareceu em {CLIENT_TIMEOUT}s`)
	local remote = folder:WaitForChild(name, CLIENT_TIMEOUT)
	assert(remote, `Net: o RemoteEvent "{name}" nao apareceu em {CLIENT_TIMEOUT}s`)
	assert(remote:IsA("RemoteEvent"), `Net: "{name}" deveria ser um RemoteEvent`)
	return remote
end

return Net
