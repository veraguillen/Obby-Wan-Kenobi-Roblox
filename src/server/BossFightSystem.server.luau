--!strict
-- Version MVP del jefe (1 fase, 1 barra de vida, 1 ataque) para validar el
-- loop de combate. El equipo gana golpeando el nucleo directamente. El
-- unico ataque es una onda expansiva: en vez de un empujon fisico fuerte
-- (que podia sacar al jugador de la plataforma al vacio por Boss_Arena no
-- tener muros perimetrales -- problema de balance ya señalado), ser
-- alcanzado por la onda llama a RescueSystem.KnockDown, que lo derriba en el
-- lugar (12-15s recuperable por un companero o por cuerda de equipo) sin
-- moverlo de la arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))
local RescueSystem = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RescueSystem"))

local RoomManagerScript = ServerScriptService:WaitForChild("Server"):WaitForChild("RoomManager")
local RoundStarted = RoomManagerScript:WaitForChild("RoundStarted") :: BindableEvent

-- Señal server-only (no replica al cliente) para que otros sistemas (ej.
-- RoomManager.server.luau) sepan cuando el jefe fue derrotado, sin que
-- BossFightSystem conozca ni dependa de ellos. Mismo patron que
-- RoundStarted en RoomManager.server.luau y CheckpointReached en
-- CheckpointSystem.server.luau.
local BossDefeated = Instance.new("BindableEvent")
BossDefeated.Name = "BossDefeated"
BossDefeated.Parent = script

local BossArena = Workspace:WaitForChild("Boss_Arena")
local BossCore = BossArena:WaitForChild("Boss_Core") :: BasePart
local HealthBarGui = BossCore:WaitForChild("HealthBarGui")
local HealthFill = HealthBarGui:WaitForChild("Background"):WaitForChild("Fill") :: Frame
local VictoryGui = BossCore:WaitForChild("VictoryGui") :: BillboardGui

local BOSS_MAX_HEALTH = 100
local DAMAGE_PER_HIT = 10
local HIT_COOLDOWN_SECONDS = 0.5
local ATTACK_REST_SECONDS = 5
local WARNING_DURATION_SECONDS = 1.75
local WARNING_PULSE_INTERVAL = 0.2
local WARNING_COLOR = Color3.new(1, 1, 1)
local SHOCKWAVE_RADIUS = 70

-- Inmunidad breve al entrar a Boss_Arena: el loop de ataque de mas abajo
-- corre desde que arranca el server, en un ciclo continuo (~ATTACK_REST_
-- SECONDS + WARNING_DURATION_SECONDS) totalmente ajeno a cuando llega un
-- jugador -- sin esto, un jugador podia aparecer (CheckpointSystem.server.
-- luau, advanceCharacterToNextStage) en cualquier punto del ciclo, incluido
-- el instante exacto de executeShockwave, sin haber visto ningun aviso.
-- Attribute separado de LastRespawnTime (que ya usa DynamiteSabotageSystem.
-- server.luau para su propia inmunidad post-caida en las stages) a
-- proposito, para no acoplar dos sistemas de inmunidad con semantica
-- distinta -- este es especifico de la llegada a Boss_Arena.
local BOSS_ARENA_ENTRY_GRACE_SECONDS = 3

local originalCoreColor = BossCore.Color
local bossHealth = BOSS_MAX_HEALTH
local defeated = false
local hitDebounce: { [number]: boolean } = {}

local function updateHealthBar()
	HealthFill.Size = UDim2.new(bossHealth / BOSS_MAX_HEALTH, 0, 1, 0)
end

local function triggerVictory()
	defeated = true
	VictoryGui.Enabled = true
	BossDefeated:Fire()
end

local function resetBoss()
	bossHealth = BOSS_MAX_HEALTH
	defeated = false
	BossCore.Color = originalCoreColor
	VictoryGui.Enabled = false
	updateHealthBar()
end

RoundStarted.Event:Connect(resetBoss)

local function onCoreTouched(hit: BasePart)
	if defeated then
		return
	end

	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	-- Un jugador derribado (RescueSystem.KnockDown) queda inmovil con
	-- PlatformStand=true cerca del nucleo: su fisica suelta puede tocarlo
	-- por accidente sin que nadie lo ataque a proposito. No cuenta como hit.
	if PlayerDataModule.IsDowned(player) then
		return
	end

	if hitDebounce[player.UserId] then
		return
	end
	hitDebounce[player.UserId] = true
	task.delay(HIT_COOLDOWN_SECONDS, function()
		hitDebounce[player.UserId] = nil
	end)

	bossHealth = math.max(0, bossHealth - DAMAGE_PER_HIT)
	updateHealthBar()

	if bossHealth <= 0 then
		triggerVictory()
	end
end

BossCore.Touched:Connect(onCoreTouched)

local function hasBossArenaEntryImmunity(player: Player): boolean
	local entryTime = player:GetAttribute("BossArenaEntryTime")
	if typeof(entryTime) ~= "number" then
		return false
	end
	return (Workspace:GetServerTimeNow() - entryTime) < BOSS_ARENA_ENTRY_GRACE_SECONDS
end

local function executeShockwave()
	for _, player in ipairs(Players:GetPlayers()) do
		if hasBossArenaEntryImmunity(player) then
			continue
		end

		local character = player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			local distance = (humanoidRootPart.Position - BossCore.Position).Magnitude
			if distance <= SHOCKWAVE_RADIUS then
				RescueSystem.KnockDown(player)
			end
		end
	end
end

task.spawn(function()
	while true do
		if defeated then
			task.wait(0.5)
			continue
		end

		task.wait(ATTACK_REST_SECONDS)
		if defeated then
			continue
		end

		local warningElapsed = 0
		local pulseOn = false
		while warningElapsed < WARNING_DURATION_SECONDS do
			if defeated then
				break
			end
			pulseOn = not pulseOn
			BossCore.Color = pulseOn and WARNING_COLOR or originalCoreColor
			task.wait(WARNING_PULSE_INTERVAL)
			warningElapsed += WARNING_PULSE_INTERVAL
		end
		BossCore.Color = originalCoreColor

		if defeated then
			continue
		end

		executeShockwave()
	end
end)
