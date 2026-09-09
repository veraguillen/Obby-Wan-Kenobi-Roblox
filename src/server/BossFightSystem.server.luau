--!strict
-- Version MVP del jefe (1 fase, 1 barra de vida, 1 ataque) para validar el
-- loop de combate. El equipo gana golpeando el nucleo directamente. El
-- unico ataque es una onda expansiva que empuja a los jugadores cercanos
-- hacia afuera; Boss_Arena no tiene muros perimetrales, asi que un empujon
-- fuerte puede sacarlos de la plataforma al vacio, donde el monitor de
-- caida ya existente (CheckpointSystem.server.luau) se encarga del respawn
-- sin necesitar logica nueva aqui.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local RoomManagerScript = ServerScriptService:WaitForChild("Server"):WaitForChild("RoomManager")
local RoundStarted = RoomManagerScript:WaitForChild("RoundStarted") :: BindableEvent

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
local KNOCKBACK_HORIZONTAL_SPEED = 85
local KNOCKBACK_VERTICAL_SPEED = 35
local KNOCKBACK_DURATION_SECONDS = 0.4

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

local function applyKnockback(humanoidRootPart: BasePart)
	local direction = humanoidRootPart.Position - BossCore.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(1, 0, 0)
	else
		direction = direction.Unit
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVelocity.Velocity = direction * KNOCKBACK_HORIZONTAL_SPEED + Vector3.new(0, KNOCKBACK_VERTICAL_SPEED, 0)
	bodyVelocity.Parent = humanoidRootPart
	task.delay(KNOCKBACK_DURATION_SECONDS, function()
		bodyVelocity:Destroy()
	end)
end

local function executeShockwave()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			local distance = (humanoidRootPart.Position - BossCore.Position).Magnitude
			if distance <= SHOCKWAVE_RADIUS then
				applyKnockback(humanoidRootPart)
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
