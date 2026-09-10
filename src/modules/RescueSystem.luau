--!strict
-- Derribo/rescate compartido por equipo. RescueSystem.KnockDown(player) deja
-- a un jugador "caido pero recuperable" 12-15s, sin tocar Humanoid.Health en
-- ningun momento (hoy nada en el proyecto usa Health; este sistema tampoco
-- empieza a usarlo, para no depender de si Humanoid.Died se puede prevenir
-- de forma determinista). El derribo es 100% simulado: freeze de movimiento +
-- PlatformStand + giro del HumanoidRootPart, mas un BillboardGui con
-- countdown y un ProximityPrompt (mismo patron visual que HealthBarGui/
-- VictoryGui en BossFightSystem.server.luau).
--
-- Un companero del MISMO equipo revive sosteniendo el ProximityPrompt 3s.
-- Como las pistas son paralelas y sin interseccion, solo companeros del
-- mismo equipo pueden llegar fisicamente al derribado -- no hace falta
-- validar "mismo equipo" mas alla de excluir que se revivan a si mismos.
--
-- Si el timer expira sin revive:
--   - Si el equipo tiene una cuerda disponible (RescueState), se gasta:
--     teletransporta al ultimo checkpoint y resta 1 Vida, reusando
--     LifeLossModule.HandleLifeLoss (isRealDeath = false), igual que una
--     caida al vacio.
--   - Si no quedan cuerdas, el jugador pasa a "esperando checkpoint": resta
--     1 Vida, queda congelado (sin PlatformStand, sin camara de espectador)
--     hasta que CUALQUIER companero de su equipo toque un Checkpoint_Pad
--     nuevo (senal CheckpointReached de CheckpointSystem.server.luau), momento
--     en el que reaparece alli.
--
-- La caida al vacio (CheckpointSystem.server.luau, isRealDeath = false) NO
-- pasa por este sistema -- sigue exactamente igual que antes.
--
-- ModuleScript (no Script) porque necesita ser requerido: BossFightSystem.
-- server.luau llama RescueSystem.KnockDown(player) en su onda expansiva.
-- Ese mismo require() en el arranque del servidor es lo que dispara el
-- setup de abajo (listeners de RoundStarted/CheckpointReached) -- antes,
-- cuando esto era un Script, Roblox lo arrancaba solo; ahora lo arranca
-- quien lo requiere por primera vez.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))
local RescueState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RescueState"))
local LifeLossModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LifeLossModule"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RescueMessageEvent = RemoteEvents:WaitForChild("RescueMessageEvent") :: RemoteEvent

local ServerFolder = ServerScriptService:WaitForChild("Server")

local RoomManagerScript = ServerFolder:WaitForChild("RoomManager")
local RoundStarted = RoomManagerScript:WaitForChild("RoundStarted") :: BindableEvent

local CheckpointSystemScript = ServerFolder:WaitForChild("CheckpointSystem")
local CheckpointReached = CheckpointSystemScript:WaitForChild("CheckpointReached") :: BindableEvent

local DOWN_DURATION_SECONDS = 13
local REVIVE_HOLD_SECONDS = 3
local COUNTDOWN_TICK_SECONDS = 0.5
local WAITING_FOR_CHECKPOINT_TIMEOUT_SECONDS = 30
local DEFAULT_WALK_SPEED = 16
local DEFAULT_JUMP_POWER = 50
local DEFAULT_JUMP_HEIGHT = 7.2
local BILLBOARD_STUD_OFFSET = Vector3.new(0, 3, 0)

local RescueSystem = {}

-- Invalida timers/prompts en vuelo cuando el jugador es revivido, arranca
-- una ronda nueva, o se lo vuelve a derribar (no deberia pasar, pero por las
-- dudas queda protegido por token en vez de por bandera simple).
local downTokens: { [Player]: number } = {}

-- Mismo patron de token que downTokens, pero para WaitingForCheckpoint:
-- permite que CheckpointReached y el timeout de 30s de abajo se invaliden
-- mutuamente -- el primero de los dos que libera al jugador gana.
local waitTokens: { [Player]: number } = {}

local function restoreMovement(humanoid: Humanoid)
	humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	humanoid.JumpPower = DEFAULT_JUMP_POWER
	humanoid.JumpHeight = DEFAULT_JUMP_HEIGHT
	humanoid.PlatformStand = false
end

local function freezeMovement(humanoid: Humanoid)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function destroyDownedGui(character: Model)
	local gui = character:FindFirstChild("DownedStatusGui")
	if gui then
		gui:Destroy()
	end
end

local function createDownedGui(character: Model, humanoidRootPart: BasePart): (TextLabel, ProximityPrompt)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DownedStatusGui"
	billboard.Adornee = humanoidRootPart
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffset = BILLBOARD_STUD_OFFSET
	billboard.AlwaysOnTop = true
	billboard.Parent = character

	local label = Instance.new("TextLabel")
	label.Name = "DownedLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 0.3, 0.3)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Reanimar"
	prompt.ObjectText = "Companero derribado"
	prompt.HoldDuration = REVIVE_HOLD_SECONDS
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = humanoidRootPart

	return label, prompt
end

-- Limpia el estado "derribado" (revive manual o inicio de ronda). No toca
-- Vidas ni IsWaitingForCheckpoint -- eso lo maneja cada camino por separado.
local function clearDowned(player: Player, character: Model?)
	PlayerDataModule.SetDownedState(player, false, nil)
	player:SetAttribute("IsDowned", false)
	player:SetAttribute("DownedUntil", nil)

	if character then
		destroyDownedGui(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			restoreMovement(humanoid)
		end
	end
end

function RescueSystem.KnockDown(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not humanoidRootPart then
		return
	end

	if PlayerDataModule.IsDowned(player) or PlayerDataModule.IsWaitingForCheckpoint(player) then
		return
	end

	local downedUntil = Workspace:GetServerTimeNow() + DOWN_DURATION_SECONDS
	PlayerDataModule.SetDownedState(player, true, downedUntil)
	player:SetAttribute("IsDowned", true)
	player:SetAttribute("DownedUntil", downedUntil)

	freezeMovement(humanoid)
	humanoid.PlatformStand = true
	character:PivotTo(character:GetPivot() * CFrame.Angles(math.rad(90), 0, 0))

	local label, prompt = createDownedGui(character, humanoidRootPart)

	local myToken = (downTokens[player] or 0) + 1
	downTokens[player] = myToken
	local revived = false

	local triggeredConnection: RBXScriptConnection
	triggeredConnection = prompt.Triggered:Connect(function(reviver: Player)
		if reviver == player then
			RescueMessageEvent:FireClient(reviver, "No podes reanimarte a vos mismo")
			return
		end
		if PlayerDataModule.GetAssignedTrack(reviver) ~= PlayerDataModule.GetAssignedTrack(player) then
			RescueMessageEvent:FireClient(reviver, "Solo tu equipo puede reanimarte")
			return
		end
		if downTokens[player] ~= myToken then
			return
		end
		revived = true
		triggeredConnection:Disconnect()
		clearDowned(player, player.Character)
	end)

	task.spawn(function()
		while downTokens[player] == myToken and not revived do
			local remaining = downedUntil - Workspace:GetServerTimeNow()
			if remaining <= 0 then
				break
			end
			label.Text = string.format("DERRIBADO (%ds)", math.ceil(remaining))
			task.wait(COUNTDOWN_TICK_SECONDS)
		end

		if downTokens[player] ~= myToken or revived then
			return
		end

		triggeredConnection:Disconnect()

		local currentCharacter = player.Character
		local trackName = PlayerDataModule.GetAssignedTrack(player)

		if trackName and RescueState.TrySpendCord(trackName) then
			clearDowned(player, currentCharacter)
			if currentCharacter then
				LifeLossModule.HandleLifeLoss(player, currentCharacter, false)
			end
			return
		end

		-- Sin cuerdas: si es su ultima vida (Lives <= 1, mismo umbral que ya
		-- usa LifeLossModule para decidir "sin vidas restantes"), no lo dejamos
		-- esperando un checkpoint para siempre -- sigue el mismo camino que ya
		-- existe para ese caso (reset de progreso + vuelta al lobby, incluido
		-- el reset de AssignedTrack en PlayerDataModule Y el Attribute juntos).
		-- isRealDeath = true aca no es una muerte real de Roblox: es el unico
		-- parametro de la funcion existente que dispara ese reset completo, y
		-- no se puede tocar LifeLossModule.luau para agregar un caso nuevo.
		local data = PlayerDataModule.GetPlayerData(player)
		if data and data.Lives <= 1 then
			clearDowned(player, currentCharacter)
			if currentCharacter then
				LifeLossModule.HandleLifeLoss(player, currentCharacter, true)
			end
			return
		end

		-- Le quedan vidas de sobra: pasa a esperar el proximo checkpoint del equipo.
		PlayerDataModule.SetDownedState(player, false, nil)
		player:SetAttribute("IsDowned", false)
		player:SetAttribute("DownedUntil", nil)
		PlayerDataModule.SetWaitingForCheckpoint(player, true)
		player:SetAttribute("IsWaitingForCheckpoint", true)

		if currentCharacter then
			destroyDownedGui(currentCharacter)
			if data then
				PlayerDataModule.SetLives(player, data.Lives - 1)
			end
			-- Sigue frenado (ya lo estaba desde KnockDown); solo se suelta el
			-- PlatformStand para que espere de pie, no tirado en el piso.
			local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
			if currentHumanoid then
				currentHumanoid.PlatformStand = false
			end
		end

		-- Failsafe: si el jugador es el unico de su equipo (1v1, o el resto
		-- tambien cayo), CheckpointReached nunca va a disparar para su track y
		-- quedaria congelado para siempre. A los 30s lo libera igual, sin
		-- cuerda ni companero, al ultimo checkpoint que ya tenia guardado
		-- (misma fuente que usa el camino normal -- PlayerDataModule.
		-- GetLastCheckpointCFrame). Si CheckpointReached ya lo libero antes,
		-- waitTokens no coincide o IsWaitingForCheckpoint ya es false, y esto
		-- no hace nada.
		local myWaitToken = (waitTokens[player] or 0) + 1
		waitTokens[player] = myWaitToken
		task.delay(WAITING_FOR_CHECKPOINT_TIMEOUT_SECONDS, function()
			if waitTokens[player] ~= myWaitToken or not PlayerDataModule.IsWaitingForCheckpoint(player) then
				return
			end

			PlayerDataModule.SetWaitingForCheckpoint(player, false)
			player:SetAttribute("IsWaitingForCheckpoint", false)
			player:SetAttribute("LastRespawnTime", Workspace:GetServerTimeNow())

			local fallbackCharacter = player.Character
			if fallbackCharacter then
				local fallbackCFrame = PlayerDataModule.GetLastCheckpointCFrame(player)
				if fallbackCFrame then
					fallbackCharacter:PivotTo(fallbackCFrame)
				end
				local fallbackHumanoid = fallbackCharacter:FindFirstChildOfClass("Humanoid")
				if fallbackHumanoid then
					restoreMovement(fallbackHumanoid)
				end
			end
		end)
	end)
end

CheckpointReached.Event:Connect(function(trackName: string, stageNumber: number, checkpointCFrame: CFrame)
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataModule.GetAssignedTrack(player) == trackName and PlayerDataModule.IsWaitingForCheckpoint(player) then
			waitTokens[player] = (waitTokens[player] or 0) + 1
			PlayerDataModule.SetWaitingForCheckpoint(player, false)
			player:SetAttribute("IsWaitingForCheckpoint", false)
			PlayerDataModule.SetCheckpoint(player, stageNumber, checkpointCFrame)
			player:SetAttribute("LastRespawnTime", Workspace:GetServerTimeNow())

			local character = player.Character
			if character then
				character:PivotTo(checkpointCFrame)
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					restoreMovement(humanoid)
				end
			end
		end
	end
end)

RoundStarted.Event:Connect(function()
	RescueState.ResetCords()
	for _, player in ipairs(Players:GetPlayers()) do
		downTokens[player] = (downTokens[player] or 0) + 1

		if PlayerDataModule.IsWaitingForCheckpoint(player) then
			PlayerDataModule.SetWaitingForCheckpoint(player, false)
			player:SetAttribute("IsWaitingForCheckpoint", false)
		end

		if PlayerDataModule.IsDowned(player) then
			clearDowned(player, player.Character)
		end
	end
end)

return RescueSystem
