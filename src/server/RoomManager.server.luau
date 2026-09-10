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
local ServerScriptService = game:GetService("ServerScriptService")
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

-- Señal de fin de ronda por victoria: RoomManager no conoce el combate
-- contra el jefe, solo escucha este BindableEvent (mismo patron inverso que
-- RoundStarted) para saber cuando puede volver a abrir la sala.
local BossFightSystemScript = ServerScriptService:WaitForChild("Server"):WaitForChild("BossFightSystem")
local BossDefeated = BossFightSystemScript:WaitForChild("BossDefeated") :: BindableEvent

-- Requerido para RescueSystem.ClearPlayerRescueState en endRound() (ver mas
-- abajo). IMPORTANTE: este require debe quedar DESPUES de que RoundStarted
-- ya fue creado arriba -- RescueSystem.luau espera (WaitForChild) por esa
-- misma instancia al cargar por primera vez, y si este require corriera
-- antes de la creacion de RoundStarted se trabaria en un deadlock (este
-- mismo script, bloqueado esperandose a si mismo).
local RescueSystem = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RescueSystem"))

local Lobby = Workspace:WaitForChild("Lobby")

local COUNTDOWN_SECONDS = 10
local LANDING_HEIGHT_OFFSET = 4
local ROUND_TIMEOUT_SECONDS = 20 * 60

-- Polling de presencia en cola (reemplaza el viejo TouchEnded del portal,
-- que disparaba en ~0.3s al cruzar el TouchZone de 1 stud caminando a
-- WalkSpeed normal -- ver DEFAULT_WALK_SPEED en RescueSystem.luau -- y
-- vaciaba la cola de jugadores que segun caminando con normalidad).
-- Mismo intervalo de chequeo que usa CheckpointSystem.server.luau
-- (POSITION_CHECK_INTERVAL) para su propio polling de posicion.
local QUEUE_PRESENCE_CHECK_INTERVAL = 0.5
-- Los 5 portales de cada equipo estan alineados en Lobby (default.project.
-- json) separados 100 studs entre si (ej. Portal_Ninja_1..5 en Z = -1100,
-- -1000, -900, -800, -700, mismo X). 60 = mitad de esa separacion (50) mas
-- un margen de 10 studs, asi el radio de un portal cubre sin huecos el
-- punto medio hacia el portal vecino. Se queda comodo dentro del Lobby: el
-- portal ninja mas cercano al muro oeste (X=300) tiene el muro 101 studs
-- mas alla (Wall_West en X=199), y el LobbySpawn (X=500) esta a 200 studs
-- de cualquier portal ninja/cowboy -- 60 nunca llega a cruzar hacia el
-- spawn ni hacia el equipo rival.
local QUEUE_PRESENCE_RADIUS = 60
local QUEUE_ABANDON_GRACE_SECONDS = 2

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

-- Jugadores que entraron a la ronda actualmente "InGame" (copia de
-- ninjaQueue/cowboyQueue tomada en launchRace, antes de vaciarlas). Mientras
-- este roster no quede vacio por una de las 3 vias de fin de ronda, state se
-- mantiene en "InGame" y no se puede arrancar una cuenta regresiva nueva.
local roundRoster: { [Player]: boolean } = {}
local roundTimeoutThread: thread? = nil

-- Desde cuando (Workspace:GetServerTimeNow()) un jugador en cola esta fuera
-- del radio de todos los portales de su lado, de forma sostenida. nil =
-- esta dentro del radio (o no se le esta trackeando ahora mismo).
local queueOutsideSince: { [Player]: number } = {}

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

-- Posiciones (en el mundo) de los TouchZone de todos los portales de un
-- lado (ninja/cowboy). Se calcula una sola vez al arrancar: los portales
-- son geometria estatica de default.project.json (Anchored = true), no se
-- mueven en runtime.
local function getPortalPositionsForTrack(trackName: string): { Vector3 }
	local positions: { Vector3 } = {}
	for _, portal in ipairs(Lobby:GetChildren()) do
		local touchZone = portal:FindFirstChild("TouchZone")
		if touchZone and touchZone:IsA("BasePart") and touchZone:GetAttribute("TargetTrack") == trackName then
			table.insert(positions, touchZone.Position)
		end
	end
	return positions
end

local ninjaPortalPositions = getPortalPositionsForTrack("Track_A")
local cowboyPortalPositions = getPortalPositionsForTrack("Track_B")

local function isWithinRadiusOfAny(position: Vector3, targets: { Vector3 }, radius: number): boolean
	for _, target in ipairs(targets) do
		if (position - target).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- Solo para el print de diagnostico [Queue] de abajo -- no participa de
-- ninguna decision de remocion (esa sigue siendo isWithinRadiusOfAny).
local function getNearestDistance(position: Vector3, targets: { Vector3 }): number
	local nearest = math.huge
	for _, target in ipairs(targets) do
		local distance = (position - target).Magnitude
		if distance < nearest then
			nearest = distance
		end
	end
	return nearest
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
	print(string.format("[Queue] buildStatusText: ninjaCount=%d cowboyCount=%d", ninjaCount, cowboyCount))
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
local endRound: () -> ()

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
--
-- state se queda en "InGame" -- ya NO vuelve a "Idle" aca. Antes lo hacia de
-- forma sincronica en esta misma funcion, lo que dejaba la sala lista para
-- una cuenta regresiva nueva mientras la carrera recien arrancada seguia en
-- curso (RoundStarted espurio, contaminaba derribo/espera de la carrera
-- viva). Ahora la sala solo vuelve a "Idle" via endRound(), en alguna de las
-- 3 condiciones de fin de ronda.
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

	table.clear(roundRoster)
	for player in pairs(ninjaQueue) do
		roundRoster[player] = true
		RoomStatusEvent:FireClient(player, "", false)
	end
	for player in pairs(cowboyQueue) do
		roundRoster[player] = true
		RoomStatusEvent:FireClient(player, "", false)
	end

	table.clear(ninjaQueue)
	table.clear(cowboyQueue)
	remainingSeconds = COUNTDOWN_SECONDS
	countdownThread = nil
	updateDisplays()

	if roundTimeoutThread then
		task.cancel(roundTimeoutThread)
	end
	roundTimeoutThread = task.delay(ROUND_TIMEOUT_SECONDS, function()
		roundTimeoutThread = nil
		endRound()
	end)
end

-- Termina la ronda "InGame" actual por cualquiera de las 3 vias (jefe
-- derrotado, roster vacio por desconexion total, o timeout de seguridad) y
-- deja la sala lista para una cuenta regresiva nueva. Idempotente: si ya no
-- hay ronda activa (state ~= "InGame"), no hace nada -- evita doble reset si
-- dos condiciones de fin de ronda se disparan casi juntas.
endRound = function()
	if state ~= "InGame" then
		return
	end

	if roundTimeoutThread then
		task.cancel(roundTimeoutThread)
		roundTimeoutThread = nil
	end

	for player in pairs(roundRoster) do
		PlayerDataModule.SetAssignedTrack(player, nil)
		player:SetAttribute("AssignedTrack", nil)
		-- Sin esto, un jugador que sigue derribado/esperando checkpoint
		-- cuando termina la ronda (jefe derrotado, timeout, o el resto del
		-- equipo se desconecto) arrastraba ese estado hasta el proximo
		-- RoundStarted -- y si el mismo se desconectaba y reconectaba en el
		-- medio, lo arrastraba mas alla de eso tambien (ver
		-- PlayerDataModule.CleanupPlayer mas abajo). Mismo reset que ya
		-- hace RescueSystem en su propio listener de RoundStarted, al
		-- arrancar la ronda siguiente -- esto lo hace tambien al cerrar
		-- esta.
		RescueSystem.ClearPlayerRescueState(player)
	end
	table.clear(roundRoster)

	state = "Idle"
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
	-- Via (b) de fin de ronda: si el que se desconecta formaba parte del
	-- roster de la ronda "InGame" actual, sacarlo; si eso deja el roster
	-- vacio, ya no queda nadie corriendo la pista y la ronda termina.
	-- Independiente del chequeo de wasQueued de abajo -- una vez que la
	-- carrera arranca, los jugadores ya no estan en ninjaQueue/cowboyQueue
	-- (launchRace las vacia), solo en roundRoster.
	if roundRoster[player] then
		roundRoster[player] = nil
		if next(roundRoster) == nil then
			endRound()
		end
	end

	local wasQueued = ninjaQueue[player] or cowboyQueue[player]
	ninjaQueue[player] = nil
	cowboyQueue[player] = nil
	queueOutsideSince[player] = nil

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

	local queueSizeAfterAdd = countQueue(trackName == "Track_A" and ninjaQueue or cowboyQueue)
	print(string.format("[Queue] onPortalTouched: %s -> %s (tamano cola=%d)", player.Name, trackName, queueSizeAfterAdd))

	updateDisplays()
	tryStartCountdown()
end

-- Contraparte de onPortalTouched: mientras la ronda no arranco (state ==
-- "Idle"), vigila por polling (no por TouchEnded -- ver comentario de
-- QUEUE_PRESENCE_CHECK_INTERVAL mas arriba: el TouchZone es un gate de 1
-- stud que cualquier caminata normal cruza en fracciones de segundo, asi
-- que TouchEnded disparaba con jugadores que jamas se habian ido) si algun
-- jugador en cola se alejo mas de QUEUE_PRESENCE_RADIUS de TODOS los
-- portales de su lado, sostenido por QUEUE_ABANDON_GRACE_SECONDS. Recien
-- ahi lo saca de la cola -- tolera pasar caminando cerca de mas de un
-- portal del mismo lado sin ser expulsado.
local function checkPlayerPresence(player: Player, portalPositions: { Vector3 }, now: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	if isWithinRadiusOfAny(humanoidRootPart.Position, portalPositions, QUEUE_PRESENCE_RADIUS) then
		queueOutsideSince[player] = nil
		return
	end

	local outsideSince = queueOutsideSince[player]
	if not outsideSince then
		queueOutsideSince[player] = now
		return
	end

	if now - outsideSince >= QUEUE_ABANDON_GRACE_SECONDS then
		local nearestDistance = getNearestDistance(humanoidRootPart.Position, portalPositions)
		print(string.format(
			"[Queue] checkQueuePresence: remueve a %s (fuera %.1fs, distancia al portal mas cercano=%.1f)",
			player.Name,
			now - outsideSince,
			nearestDistance
		))
		removePlayerFromQueues(player)
	end
end

local function checkQueuePresence()
	if state ~= "Idle" then
		table.clear(queueOutsideSince)
		return
	end

	local now = Workspace:GetServerTimeNow()

	for player in pairs(ninjaQueue) do
		checkPlayerPresence(player, ninjaPortalPositions, now)
	end
	for player in pairs(cowboyQueue) do
		checkPlayerPresence(player, cowboyPortalPositions, now)
	end
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
			end
		end
	end
end

connectPortalTouchZones()

task.spawn(function()
	while true do
		task.wait(QUEUE_PRESENCE_CHECK_INTERVAL)
		checkQueuePresence()
	end
end)

-- Via (a) de fin de ronda: el jefe fue derrotado.
BossDefeated.Event:Connect(endRound)

Players.PlayerRemoving:Connect(removePlayerFromQueues)

-- Sin esto, playerData[player.UserId] (PlayerDataModule.luau) nunca se
-- borraba al desconectarse -- si el mismo jugador (mismo UserId real de
-- Roblox) volvia a entrar, heredaba integro su estado viejo (AssignedTrack,
-- IsDowned, IsWaitingForCheckpoint, etc.), porque onPortalTouched solo
-- llama PlayerDataModule.InitializePlayer cuando GetPlayerData no encuentra
-- nada. Con el leak, "nada" nunca pasaba.
Players.PlayerRemoving:Connect(function(player: Player)
	PlayerDataModule.CleanupPlayer(player)
end)

-- PENDIENTE (fuera de alcance de este fix): hoy el modelo es de una sola
-- ronda global a la vez -- un unico Track_A/Track_B/Boss_Arena/DynamiteState/
-- RescueState singleton, con un unico roundRoster/state en este script. Los
-- 5 portales por equipo (via ServerIndex en default.project.json) ya
-- soportan multiples puntos de entrada a la MISMA cola, no salas paralelas
-- independientes. Soportar rondas realmente simultaneas (multi-sala)
-- requiere instanciar Track_A/Track_B/Boss_Arena por sesion y volver
-- DynamiteState/RescueState/BossFightSystem keyed por sesion -- cambio de
-- arquitectura mayor, a encarar recien cuando se observe en la practica que
-- jugadores reales esperan por una sala ocupada, no antes.

updateDisplays()
