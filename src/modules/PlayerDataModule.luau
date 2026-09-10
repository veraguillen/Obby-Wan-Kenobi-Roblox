--!strict
-- Datos temporales de sesion por jugador. Autoridad exclusiva del servidor:
-- toda funcion que modifica estado verifica RunService:IsServer(), y las
-- lecturas devuelven copias para que un LocalScript no pueda mutar la tabla interna.

local RunService = game:GetService("RunService")

export type PlayerData = {
	Lives: number,
	MaxLives: number,
	CurrentStage: number,
	LastCheckpointCFrame: CFrame?,
	AssignedTrack: string?,
	IsDowned: boolean,
	DownedUntil: number?,
	IsWaitingForCheckpoint: boolean,
}

local PlayerDataModule = {}

local playerData: { [number]: PlayerData } = {}

local function isServer(): boolean
	return RunService:IsServer()
end

local function copyData(data: PlayerData): PlayerData
	return {
		Lives = data.Lives,
		MaxLives = data.MaxLives,
		CurrentStage = data.CurrentStage,
		LastCheckpointCFrame = data.LastCheckpointCFrame,
		AssignedTrack = data.AssignedTrack,
		IsDowned = data.IsDowned,
		DownedUntil = data.DownedUntil,
		IsWaitingForCheckpoint = data.IsWaitingForCheckpoint,
	}
end

function PlayerDataModule.InitializePlayer(player: Player): PlayerData?
	if not isServer() then
		warn("PlayerDataModule.InitializePlayer must be called from the server")
		return nil
	end

	local data: PlayerData = {
		Lives = 5,
		MaxLives = 5,
		CurrentStage = 1,
		LastCheckpointCFrame = nil,
		AssignedTrack = nil,
		IsDowned = false,
		DownedUntil = nil,
		IsWaitingForCheckpoint = false,
	}
	playerData[player.UserId] = data
	return copyData(data)
end

function PlayerDataModule.GetPlayerData(player: Player): PlayerData?
	local data = playerData[player.UserId]
	if not data then
		return nil
	end
	return copyData(data)
end

function PlayerDataModule.SetAssignedTrack(player: Player, track: string?)
	if not isServer() then
		warn("PlayerDataModule.SetAssignedTrack must be called from the server")
		return
	end
	local data = playerData[player.UserId]
	if not data then
		return
	end
	data.AssignedTrack = track
end

function PlayerDataModule.GetAssignedTrack(player: Player): string?
	local data = playerData[player.UserId]
	return data and data.AssignedTrack or nil
end

function PlayerDataModule.SetDownedState(player: Player, isDowned: boolean, downedUntil: number?)
	if not isServer() then
		warn("PlayerDataModule.SetDownedState must be called from the server")
		return
	end
	local data = playerData[player.UserId]
	if not data then
		return
	end
	data.IsDowned = isDowned
	data.DownedUntil = downedUntil
end

function PlayerDataModule.IsDowned(player: Player): boolean
	local data = playerData[player.UserId]
	return data ~= nil and data.IsDowned
end

function PlayerDataModule.GetDownedUntil(player: Player): number?
	local data = playerData[player.UserId]
	return data and data.DownedUntil or nil
end

function PlayerDataModule.SetWaitingForCheckpoint(player: Player, isWaiting: boolean)
	if not isServer() then
		warn("PlayerDataModule.SetWaitingForCheckpoint must be called from the server")
		return
	end
	local data = playerData[player.UserId]
	if not data then
		return
	end
	data.IsWaitingForCheckpoint = isWaiting
end

function PlayerDataModule.IsWaitingForCheckpoint(player: Player): boolean
	local data = playerData[player.UserId]
	return data ~= nil and data.IsWaitingForCheckpoint
end

function PlayerDataModule.SetCheckpoint(player: Player, stage: number, cframe: CFrame?)
	if not isServer() then
		warn("PlayerDataModule.SetCheckpoint must be called from the server")
		return
	end
	local data = playerData[player.UserId]
	if not data then
		return
	end
	data.CurrentStage = stage
	data.LastCheckpointCFrame = cframe
end

function PlayerDataModule.GetCurrentStage(player: Player): number
	local data = playerData[player.UserId]
	return data and data.CurrentStage or 1
end

function PlayerDataModule.GetLastCheckpointCFrame(player: Player): CFrame?
	local data = playerData[player.UserId]
	return data and data.LastCheckpointCFrame or nil
end

function PlayerDataModule.SetLives(player: Player, lives: number): number?
	if not isServer() then
		warn("PlayerDataModule.SetLives must be called from the server")
		return nil
	end
	local data = playerData[player.UserId]
	if not data then
		return nil
	end
	data.Lives = math.clamp(lives, 0, data.MaxLives)
	return data.Lives
end

function PlayerDataModule.SubtractLife(player: Player): number?
	if not isServer() then
		warn("PlayerDataModule.SubtractLife must be called from the server")
		return nil
	end
	local data = playerData[player.UserId]
	if not data then
		return nil
	end
	data.Lives = math.max(0, data.Lives - 1)
	return data.Lives
end

function PlayerDataModule.RestoreLives(player: Player): number?
	if not isServer() then
		warn("PlayerDataModule.RestoreLives must be called from the server")
		return nil
	end
	local data = playerData[player.UserId]
	if not data then
		return nil
	end
	data.Lives = data.MaxLives
	return data.Lives
end

function PlayerDataModule.CleanupPlayer(player: Player)
	if not isServer() then
		warn("PlayerDataModule.CleanupPlayer must be called from the server")
		return
	end
	playerData[player.UserId] = nil
end

return PlayerDataModule
