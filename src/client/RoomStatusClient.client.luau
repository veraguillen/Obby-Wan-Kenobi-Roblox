--!strict
-- Muestra en pantalla el estado del matchmaking (espera de rivales y cuenta
-- regresiva de 10s) mientras el jugador esta en la cola de un portal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RoomStatusEvent = RemoteEvents:WaitForChild("RoomStatusEvent") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoomStatusGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.fromScale(0.5, 0.05)
statusLabel.Size = UDim2.fromScale(0.5, 0.08)
statusLabel.BackgroundTransparency = 0.3
statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Text = ""
statusLabel.Parent = screenGui

RoomStatusEvent.OnClientEvent:Connect(function(text: string, visible: boolean)
	statusLabel.Text = text
	screenGui.Enabled = visible
end)
