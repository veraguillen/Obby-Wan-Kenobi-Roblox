--!strict
-- Muestra en pantalla el checkpoint actual del equipo rival, actualizado en
-- tiempo real cada vez que cualquier jugador de esa pista avanza de checkpoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CheckpointProgressEvent = RemoteEvents:WaitForChild("CheckpointProgressEvent") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RivalCheckpointGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local rivalLabel = Instance.new("TextLabel")
rivalLabel.Name = "RivalCheckpointLabel"
rivalLabel.AnchorPoint = Vector2.new(0, 0)
rivalLabel.Position = UDim2.fromScale(0.02, 0.05)
rivalLabel.Size = UDim2.fromScale(0.3, 0.06)
rivalLabel.BackgroundTransparency = 0.3
rivalLabel.BackgroundColor3 = Color3.new(0, 0, 0)
rivalLabel.TextColor3 = Color3.new(1, 1, 1)
rivalLabel.TextScaled = true
rivalLabel.Font = Enum.Font.GothamBold
rivalLabel.Text = ""
rivalLabel.Parent = screenGui

local function updateVisibility()
	screenGui.Enabled = player:GetAttribute("HasReachedFirstCheckpoint") == true
end

player:GetAttributeChangedSignal("HasReachedFirstCheckpoint"):Connect(updateVisibility)
updateVisibility()

CheckpointProgressEvent.OnClientEvent:Connect(function(team: string, checkpointNumber: number, totalStages: number)
	local myTrack = player:GetAttribute("AssignedTrack")
	if not myTrack or team == myTrack then
		return
	end

	rivalLabel.Text = string.format("Equipo rival: Checkpoint %d/%d", checkpointNumber, totalStages)
end)
