--!strict
-- Logica compartida de perdida de vida: resta 1 Vida y reaparece en el
-- ultimo checkpoint (o Stage 1 si no hay uno, o resetea el progreso si se
-- quedo sin vidas). Extraido de CheckpointSystem.server.luau (que la usa
-- para caida al vacio / muerte real de Humanoid) para que RescueSystem.
-- server.luau pueda reusar exactamente el mismo comportamiento al gastar
-- una cuerda de rescate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))

local LANDING_HEIGHT_OFFSET = 4

local LifeLossModule = {}

local function getStagePlatform(trackName: string, stageNumber: number): BasePart?
	local track = Workspace:FindFirstChild(trackName)
	local stageFolder = track and track:FindFirstChild("Stage_" .. stageNumber)
	local platform = stageFolder and stageFolder:FindFirstChild("Stage_" .. stageNumber .. "_Platform")
	if platform and platform:IsA("BasePart") then
		return platform
	end
	return nil
end

local function respawnAtStage1(character: Model, player: Player)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local trackName = PlayerDataModule.GetAssignedTrack(player)
	if not trackName then
		local lobbySpawn = Workspace:FindFirstChild("Lobby") and Workspace.Lobby:FindFirstChild("LobbySpawn")
		if lobbySpawn and lobbySpawn:IsA("BasePart") then
			character:PivotTo(lobbySpawn.CFrame)
		end
		return
	end

	local platform = getStagePlatform(trackName, 1)
	if platform then
		character:PivotTo(CFrame.new(platform.Position + Vector3.new(0, LANDING_HEIGHT_OFFSET, 0)))
	end
end

local function respawnAtCheckpoint(character: Model, checkpointCFrame: CFrame)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end
	character:PivotTo(checkpointCFrame)
end

function LifeLossModule.HandleLifeLoss(player: Player, character: Model, isRealDeath: boolean)
	local data = PlayerDataModule.GetPlayerData(player)
	if not data then
		return
	end

	player:SetAttribute("LastRespawnTime", Workspace:GetServerTimeNow())

	if isRealDeath then
		-- Humanoid.Died deja el personaje muerto: PivotTo no lo revive, y el
		-- respawn automatico de Roblox lo manda al unico SpawnLocation del
		-- juego (Lobby.LobbySpawn). Sin esto, AssignedTrack queda pegado y
		-- onPortalTouched lo rechaza para siempre al volver a tocar un portal.
		-- Tambien se resetea el Attribute replicado: RivalCheckpointClient,
		-- DynamiteButtonClient y DynamiteSabotageSystem lo leen directamente
		-- y quedarian desincronizados con PlayerDataModule si no se limpia aqui.
		PlayerDataModule.SetAssignedTrack(player, nil)
		player:SetAttribute("AssignedTrack", nil)
	end

	if data.Lives > 1 then
		PlayerDataModule.SetLives(player, data.Lives - 1)
		local checkpointCFrame = PlayerDataModule.GetLastCheckpointCFrame(player)
		if checkpointCFrame then
			respawnAtCheckpoint(character, checkpointCFrame)
		else
			respawnAtStage1(character, player)
		end
	else
		PlayerDataModule.SetLives(player, data.MaxLives)
		PlayerDataModule.SetCheckpoint(player, 1, nil)
		respawnAtStage1(character, player)
	end
end

return LifeLossModule
