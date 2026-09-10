--!strict
-- Mensajes transitorios del sistema de derribo/rescate (ej. rechazo de
-- revive por equipo distinto o auto-revive). Mismo patron visual que el
-- mensaje de dinamita en DynamiteButtonClient.client.luau (TextLabel
-- transitorio con token para evitar que un mensaje viejo oculte uno nuevo),
-- pero en su propio ScreenGui siempre habilitado -- el de dinamita solo
-- esta habilitado para Track_B, y este mensaje debe verse sin importar el
-- equipo del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RescueMessageEvent = RemoteEvents:WaitForChild("RescueMessageEvent") :: RemoteEvent

local MESSAGE_DURATION_SECONDS = 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RescueMessageGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "RescueMessageLabel"
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.fromScale(0.5, 0.8)
messageLabel.Size = UDim2.fromScale(0.4, 0.06)
messageLabel.BackgroundTransparency = 0.3
messageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
messageLabel.TextColor3 = Color3.new(1, 1, 1)
messageLabel.TextScaled = true
messageLabel.Font = Enum.Font.GothamBold
messageLabel.Text = ""
messageLabel.Visible = false
messageLabel.Parent = screenGui

local messageToken = 0

RescueMessageEvent.OnClientEvent:Connect(function(message: string)
	messageToken += 1
	local currentToken = messageToken
	messageLabel.Text = message
	messageLabel.Visible = true
	task.delay(MESSAGE_DURATION_SECONDS, function()
		if messageToken == currentToken then
			messageLabel.Visible = false
		end
	end)
end)
