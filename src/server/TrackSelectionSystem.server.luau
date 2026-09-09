--!strict
-- Datos limpios al ingresar y spawn forzado en el Lobby mientras el jugador
-- no tenga pista asignada. La asignacion de Track_A/Track_B y el teletransporte
-- al Stage_1 son responsabilidad de RoomManager.server.luau (matchmaking por
-- equipos iguales), que llama a PlayerDataModule.SetAssignedTrack una vez que
-- arranca la cuenta regresiva.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerDataModule"))

local Lobby = Workspace:WaitForChild("Lobby")
local LobbySpawn = Lobby:WaitForChild("LobbySpawn") :: BasePart

-- ===== Inicio de sesion: datos limpios + spawn forzado en el Lobby =====

local function forceLobbySpawnIfUnassigned(player: Player, character: Model)
	if PlayerDataModule.GetAssignedTrack(player) ~= nil then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	character:PivotTo(LobbySpawn.CFrame + Vector3.new(0, 3, 0))
end

local function onPlayerAdded(player: Player)
	PlayerDataModule.InitializePlayer(player)

	player.CharacterAdded:Connect(function(character: Model)
		forceLobbySpawnIfUnassigned(player, character)
	end)

	if player.Character then
		forceLobbySpawnIfUnassigned(player, player.Character)
	end
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	onPlayerAdded(existingPlayer)
end

Players.PlayerAdded:Connect(onPlayerAdded)
