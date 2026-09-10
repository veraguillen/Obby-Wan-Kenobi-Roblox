--!strict
-- Matchmaking de equipos iguales: agrupa a los jugadores que tocan los
-- portales Ninja/Cowboy en dos colas, y solo inicia la carrera cuando ambas
-- colas tienen la misma cantidad de jugadores (>0). Al emparejar, corre una
-- cuenta regresiva de 10s; si un jugador se desconecta y rompe el balance,
-- la cuenta se cancela y la sala vuelve a esperar. Durante la cuenta, las
-- barreras de inicio quedan armadas (CanCollide = true, semi-transparentes).
-- Al llegar a 0, bloquea la sala y abre la barrera de inicio (CanCollide =
-- false) en ambas pistas a la vez; permanece abierta durante toda la carrera
-- y solo se re-arma al iniciar la cuenta regresiva de la siguiente ronda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RoomStatusEvent = RemoteEvents:WaitForChild("RoomStatusEvent") :: RemoteEvent

-- Señal server-only (no replica al cliente) para que otros sistemas
-- reseteen su propio estado al iniciar una ronda nueva, sin que RoomManager
-- conozca ni dependa de ellos. Ver DynamiteSabotageSystem.server.luau y
-- BossFightSystem.server.luau para los listeners.
local RoundStarted = Instance.new("BindableEvent")
RoundStarted.Name = "RoundStarted"
RoundStarted.Parent = script

local Lobby = Workspace:WaitForChild("Lobby")

local COUNTDOWN_SECONDS = 10
local LANDING_HEIGHT_OFFSET = 4

-- DEBUG: solo en Studio (nunca en el juego publicado) permitia arrancar la
-- cuenta regresiva sin rival real, para poder probar el flujo jugando solo/a.
-- Desactivado: se requiere siempre emparejamiento balanceado real, igual que
-- en el juego publicado (tryStartCountdown exige teamsBalanced sin excepcion
-- para Studio). Para testear en solitario, revertir puntualmente a
-- RunService:IsStudio() (linea comentada abajo) y volver a desactivar antes
-- de testear multijugador.
local ALLOW_SOLO_DEBUG_START = false
-- local ALLOW_SOLO_DEBUG_START = RunService:IsStudio()

type RoomState = "Idle" | "Countdown" | "InGame"

local state: RoomState = "Idle"
local ninjaQueue: { [Player]: boolean } = {}
local cowboyQueue: { [Player]: boolean } = {}
local remainingSeconds = COUNTDOWN_SECONDS
local countdownThread: thread? = nil

local function countQueue(queue: { [Player]: boolean }): number
	local count = 0
	for _ in pairs(queue) do
		count += 1
	end
	return count
end

local function getStage1Platform(trackName: string): BasePart?
	local track = Workspace:FindFirstChild(trackName)
	local stageFolder = track and track:FindFirstChild("Stage_1")
	local platform = stageFolder and stageFolder:FindFirstChild("Stage_1_Platform")
	if platform and platform:IsA("BasePart") then
		return platform
	end
	return nil
end

local function getStartBarrier(trackName: string): BasePart?
	local track = Workspace:FindFirstChild(trackName)
	local stageFolder = track and track:FindFirstChild("Stage_1")
	local barrier = stageFolder and stageFolder:FindFirstChild("Start_Barrier")
	if barrier and barrier:IsA("BasePart") then
		return barrier
	end
	return nil
end

local function teleportToStage1(player: Player, trackName: string)
	local character = player.Character
	local platform = getStage1Platform(trackName)
	if not character or not platform then
		return
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end
	character:PivotTo(CFrame.new(platform.Position + Vector3.new(0, LANDING_HEIGHT_OFFSET, 0)))
end

local function buildStatusText(): string
	if state == "Countdown" then
		return string.format("¡Rival encontrado! Partida inicia en: %ds", remainingSeconds)
	elseif state == "InGame" then
		return "¡CARRERA INICIADA!"
	end

	local ninjaCount = countQueue(ninjaQueue)
	local cowboyCount = countQueue(cowboyQueue)
	if ninjaCount == 0 and cowboyCount == 0 then
		return "Esperando jugadores..."
	end
	return string.format("Esperando rivales para equilibrar equipos (%dv%d)...", ninjaCount, cowboyCount)
end

local function forEachPortalStatusLabel(callback: (TextLabel) -> ())
	for _, portal in ipairs(Lobby:GetChildren()) do
		local gui = portal:FindFirstChild("StatusGui")
		local label = gui and gui:FindFirstChild("StatusLabel")
		if label and label:IsA("TextLabel") then
			callback(label)
		end
	end
end

local updateDisplays: () -> ()
local tryStartCountdown: () -> ()
local launchRace: () -> ()
local cancelCountdown: () -> ()
local removePlayerFromQueues: (Player) -> ()

updateDisplays = function()
	local text = buildStatusText()
	local isRoomActive = state ~= "Idle"

	forEachPortalStatusLabel(function(label: TextLabel)
		label.Text = text
	end)

	for player in pairs(ninjaQueue) do
		RoomStatusEvent:FireClient(player, text, isRoomActive)
	end
	for player in pairs(cowboyQueue) do
		RoomStatusEvent:FireClient(player, text, isRoomActive)
	end
end

-- Abre las barreras de salida al llegar a 0 y las deja abiertas (CanCollide =
-- false) durante todo el recorrido de la carrera. NO deben volver a cerrarse
-- aqui: solo se re-arman (CanCollide = true) en tryStartCountdown, al iniciar
-- la cuenta regresiva de la siguiente ronda.
launchRace = function()
	state = "InGame"
	remainingSeconds = 0
	updateDisplays()

	local barrierA = getStartBarrier("Track_A")
	local barrierB = getStartBarrier("Track_B")

	if barrierA then
		barrierA.CanCollide = false
		barrierA.Transparency = 1
	end
	if barrierB then
		barrierB.CanCollide = false
		barrierB.Transparency = 1
	end

	for player in pairs(ninjaQueue) do
		RoomStatusEvent:FireClient(player, "", false)
	end
	for player in pairs(cowboyQueue) do
		RoomStatusEvent:FireClient(player, "", false)
	end

	table.clear(ninjaQueue)
	table.clear(cowboyQueue)
	state = "Idle"
	remainingSeconds = COUNTDOWN_SECONDS
	countdownThread = nil
	updateDisplays()
end

tryStartCountdown = function()
	if state ~= "Idle" then
		return
	end

	local ninjaCount = countQueue(ninjaQueue)
	local cowboyCount = countQueue(cowboyQueue)
	local teamsBalanced = ninjaCount > 0 and ninjaCount == cowboyCount
	local soloDebugStart = ALLOW_SOLO_DEBUG_START and not teamsBalanced and (ninjaCount > 0 or cowboyCount > 0)
	if not teamsBalanced and not soloDebugStart then
		return
	end

	state = "Countdown"
	remainingSeconds = COUNTDOWN_SECONDS
	RoundStarted:Fire()

	local barrierA = getStartBarrier("Track_A")
	local barrierB = getStartBarrier("Track_B")

	if barrierA then
		barrierA.CanCollide = true
		barrierA.Transparency = 0.5
	end
	if barrierB then
		barrierB.CanCollide = true
		barrierB.Transparency = 0.5
	end

	for player in pairs(ninjaQueue) do
		PlayerDataModule.SetAssignedTrack(player, "Track_A")
		player:SetAttribute("AssignedTrack", "Track_A")
		teleportToStage1(player, "Track_A")
	end
	for player in pairs(cowboyQueue) do
		PlayerDataModule.SetAssignedTrack(player, "Track_B")
		player:SetAttribute("AssignedTrack", "Track_B")
		teleportToStage1(player, "Track_B")
	end

	updateDisplays()

	countdownThread = task.spawn(function()
		while state == "Countdown" and remainingSeconds > 0 do
			task.wait(1)
			if state ~= "Countdown" then
				return
			end
			remainingSeconds -= 1
			updateDisplays()
		end
		if state == "Countdown" then
			launchRace()
		end
	end)
end

cancelCountdown = function()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	state = "Idle"
	remainingSeconds = COUNTDOWN_SECONDS
end

removePlayerFromQueues = function(player: Player)
	local wasQueued = ninjaQueue[player] or cowboyQueue[player]
	ninjaQueue[player] = nil
	cowboyQueue[player] = nil

	if not wasQueued then
		return
	end

	if state == "Countdown" then
		cancelCountdown()
	end

	updateDisplays()
	tryStartCountdown()
end

local function onPortalTouched(hit: BasePart, trackName: string)
	local character = hit.Parent
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	if state ~= "Idle" then
		return
	end

	if ninjaQueue[player] or cowboyQueue[player] then
		return
	end

	local data = PlayerDataModule.GetPlayerData(player)
	if not data then
		data = PlayerDataModule.InitializePlayer(player)
	end
	if not data or data.AssignedTrack ~= nil then
		return
	end

	if trackName == "Track_A" then
		ninjaQueue[player] = true
	elseif trackName == "Track_B" then
		cowboyQueue[player] = true
	else
		return
	end

	updateDisplays()
	tryStartCountdown()
end

-- Contraparte de onPortalTouched: si el jugador camina fuera del area del
-- portal antes de que arranque la ronda (state == "Idle"), lo saca de la
-- cola para que no quede contando como fantasma. Si ya arranco el
-- countdown o la carrera, no hace nada -- el jugador ya fue asignado a un
-- track y removerlo de la cola no aplica.
local function onPortalTouchEnded(hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	if state ~= "Idle" then
		return
	end

	removePlayerFromQueues(player)
end

-- Conecta cualquier portal del Lobby que tenga un hijo "TouchZone" con el
-- atributo TargetTrack seteado ("Track_A" / "Track_B"). Soporta N portales
-- por equipo (multi-sala) sin hardcodear nombres de instancia.
local function connectPortalTouchZones()
	for _, portal in ipairs(Lobby:GetChildren()) do
		local touchZone = portal:FindFirstChild("TouchZone")
		if touchZone and touchZone:IsA("BasePart") then
			local targetTrack = touchZone:GetAttribute("TargetTrack")
			if typeof(targetTrack) == "string" then
				touchZone.Touched:Connect(function(hit: BasePart)
					onPortalTouched(hit, targetTrack :: string)
				end)
				touchZone.TouchEnded:Connect(onPortalTouchEnded)
			end
		end
	end
end

connectPortalTouchZones()

Players.PlayerRemoving:Connect(removePlayerFromQueues)

updateDisplays()
