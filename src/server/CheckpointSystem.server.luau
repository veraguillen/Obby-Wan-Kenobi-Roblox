--!strict
-- Detecta Checkpoint_Pad tocados (guarda progreso por pista) y vigila caidas
-- al vacio / muerte del Humanoid para restar vidas y reaparecer al jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))

local DynamiteState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DynamiteState"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CheckpointProgressEvent = RemoteEvents:WaitForChild("CheckpointProgressEvent") :: RemoteEvent

local LANDING_HEIGHT_OFFSET = 4
local FALL_THRESHOLD_Y = -20
local POSITION_CHECK_INTERVAL = 0.5
local CHECKPOINT_COOLDOWN_SECONDS = 1
local CHECKPOINT_FLASH_COLOR = Color3.new(0, 1, 0)
local CHECKPOINT_FLASH_DURATION = 1
local LAST_STAGE_NUMBER = 5

local function getStagePlatform(trackName: string, stageNumber: number): BasePart?
	local track = Workspace:FindFirstChild(trackName)
	local stageFolder = track and track:FindFirstChild("Stage_" .. stageNumber)
	local platform = stageFolder and stageFolder:FindFirstChild("Stage_" .. stageNumber .. "_Platform")
	if platform and platform:IsA("BasePart") then
		return platform
	end
	return nil
end

local function getBossArenaFloor(): BasePart?
	local bossArena = Workspace:FindFirstChild("Boss_Arena")
	local floor = bossArena and bossArena:FindFirstChild("Boss_Arena_Floor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

local function advanceCharacterToNextStage(character: Model, trackName: string, completedStageNumber: number)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	if completedStageNumber >= LAST_STAGE_NUMBER then
		local bossFloor = getBossArenaFloor()
		if bossFloor then
			character:PivotTo(CFrame.new(bossFloor.Position + Vector3.new(0, LANDING_HEIGHT_OFFSET, 0)))
		end
		return
	end

	local nextPlatform = getStagePlatform(trackName, completedStageNumber + 1)
	if nextPlatform then
		character:PivotTo(CFrame.new(nextPlatform.Position + Vector3.new(0, LANDING_HEIGHT_OFFSET, 0)))
	end
end

-- ===== Checkpoints =====

local checkpointDebounce: { [number]: boolean } = {}

local function flashCheckpointPad(pad: BasePart)
	local originalColor = pad.Color
	pad.Color = CHECKPOINT_FLASH_COLOR
	task.delay(CHECKPOINT_FLASH_DURATION, function()
		pad.Color = originalColor
	end)
end

local function getStageNumberFromPad(pad: BasePart): number?
	local stageFolder = pad.Parent
	if not stageFolder then
		return nil
	end
	local stageNumber = stageFolder.Name:match("Stage_(%d+)")
	return stageNumber and tonumber(stageNumber) or nil
end

local function getTrackNameFromPad(pad: BasePart): string?
	local stageFolder = pad.Parent
	local trackFolder = stageFolder and stageFolder.Parent
	if not trackFolder then
		return nil
	end
	if trackFolder.Name == "Track_A" or trackFolder.Name == "Track_B" then
		return trackFolder.Name
	end
	return nil
end

local function onCheckpointTouched(pad: BasePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	if checkpointDebounce[player.UserId] then
		return
	end
	checkpointDebounce[player.UserId] = true
	task.delay(CHECKPOINT_COOLDOWN_SECONDS, function()
		checkpointDebounce[player.UserId] = nil
	end)

	local padTrack = getTrackNameFromPad(pad)
	local data = PlayerDataModule.GetPlayerData(player)
	if not data or not padTrack or data.AssignedTrack ~= padTrack then
		return
	end

	local stageNumber = getStageNumberFromPad(pad)
	if not stageNumber then
		return
	end

	if stageNumber >= data.CurrentStage then
		local checkpointCFrame = pad.CFrame + Vector3.new(0, LANDING_HEIGHT_OFFSET, 0)
		PlayerDataModule.SetCheckpoint(player, stageNumber, checkpointCFrame)
		flashCheckpointPad(pad)
		advanceCharacterToNextStage(character :: Model, padTrack, stageNumber)
		CheckpointProgressEvent:FireAllClients(padTrack, stageNumber, LAST_STAGE_NUMBER)
		player:SetAttribute("HasReachedFirstCheckpoint", true)
		if padTrack == "Track_B" then
			DynamiteState.AddCharge()
		end
	end
end

local function connectCheckpointPads(trackFolder: Instance)
	for _, stageFolder in ipairs(trackFolder:GetChildren()) do
		local pad = stageFolder:FindFirstChild("Checkpoint_Pad")
		if pad and pad:IsA("BasePart") then
			pad.Touched:Connect(function(hit: BasePart)
				onCheckpointTouched(pad, hit)
			end)
		end
	end
end

connectCheckpointPads(Workspace:WaitForChild("Track_A"))
connectCheckpointPads(Workspace:WaitForChild("Track_B"))

-- ===== Caida al vacio / muerte =====

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

local function handleLifeLoss(player: Player, character: Model, isRealDeath: boolean)
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

local function monitorCharacter(player: Player, character: Model)
	local isProcessingRespawn = false

	local function tryHandleLifeLoss(isRealDeath: boolean)
		if isProcessingRespawn then
			return
		end
		isProcessingRespawn = true
		handleLifeLoss(player, character, isRealDeath)
		isProcessingRespawn = false
	end

	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			tryHandleLifeLoss(true)
		end)
	end

	task.spawn(function()
		while character.Parent do
			task.wait(POSITION_CHECK_INTERVAL)
			if not character.Parent then
				break
			end
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoidRootPart and humanoidRootPart.Position.Y < FALL_THRESHOLD_Y then
				tryHandleLifeLoss(false)
			end
		end
	end)
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	if existingPlayer.Character then
		monitorCharacter(existingPlayer, existingPlayer.Character)
	end
	existingPlayer.CharacterAdded:Connect(function(character: Model)
		monitorCharacter(existingPlayer, character)
	end)
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		monitorCharacter(player, character)
	end)
end)
