--!strict
-- Sabotaje "dinamita" del equipo vaquero (Track_B): destruye temporalmente
-- la Stage_N_Platform de Track_A que coincide con el stage actual del
-- vaquero que activa. Cargas de equipo otorgadas por checkpoint alcanzado
-- (ver hook en CheckpointSystem.server.luau) y cooldown compartido de
-- equipo. Jugadores que reaparecieron hace poco (LastRespawnTime, tambien
-- seteado en CheckpointSystem.server.luau) son inmunes: si hay alguno sobre
-- la plataforma objetivo, la detonacion no la destruye.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))
local DynamiteState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DynamiteState"))

local RoomManagerScript = ServerScriptService:WaitForChild("Server"):WaitForChild("RoomManager")
local RoundStarted = RoomManagerScript:WaitForChild("RoundStarted") :: BindableEvent
RoundStarted.Event:Connect(function()
	DynamiteState.ResetCharges()
end)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DynamiteActivateEvent = RemoteEvents:WaitForChild("DynamiteActivateEvent") :: RemoteEvent
local DynamiteStatusEvent = RemoteEvents:WaitForChild("DynamiteStatusEvent") :: RemoteEvent
local DynamiteMessageEvent = RemoteEvents:WaitForChild("DynamiteMessageEvent") :: RemoteEvent

local SABOTEUR_TRACK = "Track_B"
local TARGET_TRACK = "Track_A"
local TEAM_COOLDOWN_SECONDS = 25
local WARNING_SECONDS = 1.5
local EFFECT_DURATION_SECONDS = 1.75
local POST_FALL_IMMUNITY_SECONDS = 7
local SHAKE_MAGNITUDE = 0.3
local SHAKE_INTERVAL = 0.05
local ALREADY_DESTROYED_MESSAGE = "Objetivo ya destruido"

local function getStagePlatform(trackName: string, stageNumber: number): BasePart?
	local track = Workspace:FindFirstChild(trackName)
	local stageFolder = track and track:FindFirstChild("Stage_" .. stageNumber)
	local platform = stageFolder and stageFolder:FindFirstChild("Stage_" .. stageNumber .. "_Platform")
	if platform and platform:IsA("BasePart") then
		return platform
	end
	return nil
end

local function broadcastStatusToPlayer(player: Player)
	DynamiteStatusEvent:FireClient(player, DynamiteState.GetCharges(), DynamiteState.GetCooldownEndsAt())
end

local function broadcastStatusToTeam()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("AssignedTrack") == SABOTEUR_TRACK then
			broadcastStatusToPlayer(player)
		end
	end
end

DynamiteState.OnChanged(broadcastStatusToTeam)

local function isPlayerImmune(player: Player): boolean
	local lastRespawn = player:GetAttribute("LastRespawnTime")
	if typeof(lastRespawn) ~= "number" then
		return false
	end
	return (Workspace:GetServerTimeNow() - lastRespawn) < POST_FALL_IMMUNITY_SECONDS
end

local function platformHasImmunePlayer(platform: BasePart): boolean
	for _, touchingPart in ipairs(platform:GetTouchingParts()) do
		local character = touchingPart:FindFirstAncestorOfClass("Model")
		local touchingPlayer = character and Players:GetPlayerFromCharacter(character)
		if touchingPlayer and isPlayerImmune(touchingPlayer) then
			return true
		end
	end
	return false
end

local function detonate(platform: BasePart, player: Player)
	local originalCFrame = platform.CFrame
	local originalCanCollide = platform.CanCollide
	local originalTransparency = platform.Transparency

	local shakeElapsed = 0
	while shakeElapsed < WARNING_SECONDS do
		local offset = Vector3.new(
			(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE,
			0,
			(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE
		)
		platform.CFrame = originalCFrame + offset
		task.wait(SHAKE_INTERVAL)
		shakeElapsed += SHAKE_INTERVAL
	end
	platform.CFrame = originalCFrame

	if platformHasImmunePlayer(platform) then
		print("[Dynamite] Branch: platformHasImmunePlayer=true, aborting destruction for " .. platform:GetFullName())
		DynamiteMessageEvent:FireClient(player, "Objetivo inmune: alguien acaba de reaparecer ahi")
		return
	end

	platform.CanCollide = false
	platform.Transparency = 1
	task.wait(EFFECT_DURATION_SECONDS)
	platform.CanCollide = originalCanCollide
	platform.Transparency = originalTransparency
end

local function onActivateRequested(player: Player)
	if PlayerDataModule.GetAssignedTrack(player) ~= SABOTEUR_TRACK then
		print("[Dynamite] Branch: rejected, " .. player.Name .. " is not on SABOTEUR_TRACK")
		DynamiteMessageEvent:FireClient(player, "No podes usar dinamita: no estas en Track_B")
		return
	end

	local now = Workspace:GetServerTimeNow()
	if not DynamiteState.TrySpendCharge(TEAM_COOLDOWN_SECONDS, now) then
		local reason = if DynamiteState.GetCharges() <= 0 then "sin cargas disponibles" else "en cooldown de equipo"
		print("[Dynamite] Branch: rejected, " .. player.Name .. " intento activar dinamita " .. reason)
		DynamiteMessageEvent:FireClient(player, "Dinamita " .. reason)
		return
	end

	local myStage = PlayerDataModule.GetCurrentStage(player)
	local targetPlatform = getStagePlatform(TARGET_TRACK, myStage)
	print(string.format(
		"[Dynamite] targetPlatform calc: myStage=%d targetPlatform=%s position=%s",
		myStage,
		targetPlatform and targetPlatform:GetFullName() or "nil",
		targetPlatform and tostring(targetPlatform.Position) or "N/A"
	))
	if not targetPlatform then
		print("[Dynamite] Branch: targetPlatform is nil, aborting")
		DynamiteMessageEvent:FireClient(player, "No se encontro objetivo en tu stage actual")
		return
	end

	if not targetPlatform.CanCollide then
		print("[Dynamite] Branch: target already destroyed (CanCollide=false) for " .. targetPlatform:GetFullName())
		DynamiteMessageEvent:FireClient(player, ALREADY_DESTROYED_MESSAGE)
		return
	end

	print("[Dynamite] Reached detonate() call for " .. targetPlatform:GetFullName())
	DynamiteMessageEvent:FireClient(player, string.format("Detonando Stage_%d Platform en %s", myStage, TARGET_TRACK))
	task.spawn(detonate, targetPlatform, player)
end

DynamiteActivateEvent.OnServerEvent:Connect(onActivateRequested)

local function onPlayerAdded(player: Player)
	player:GetAttributeChangedSignal("AssignedTrack"):Connect(function()
		if player:GetAttribute("AssignedTrack") == SABOTEUR_TRACK then
			broadcastStatusToPlayer(player)
		end
	end)
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existingPlayer)
end

Players.PlayerAdded:Connect(onPlayerAdded)
