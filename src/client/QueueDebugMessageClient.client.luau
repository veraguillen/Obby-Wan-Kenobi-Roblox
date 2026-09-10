--!strict
-- TEMPORAL -- diagnostico del bug de conteo inestable en las colas de
-- portales (ver comentarios [Queue] en RoomManager.server.luau). Muestra en
-- pantalla los mismos 3 eventos que ya imprimen [Queue] en el server, para
-- poder verlos sin depender de la ventana de Output de Studio.
--
-- Separado a proposito de RescueMessageClient.client.luau (mismo patron
-- visual, pero su propio RemoteEvent y su propio ScreenGui) para poder
-- borrar este archivo + QueueDebugMessageEvent en default.project.json +
-- los FireClient de RoomManager.server.luau de un solo saque una vez
-- resuelto el diagnostico, sin tocar el sistema de mensajes de rescate.
--
-- BORRAR: este script, QueueDebugMessageEvent (default.project.json) y los
-- 3 QueueDebugMessageEvent:FireClient(...) en RoomManager.server.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local QueueDebugMessageEvent = RemoteEvents:WaitForChild("QueueDebugMessageEvent") :: RemoteEvent

local MESSAGE_DURATION_SECONDS = 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QueueDebugMessageGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "QueueDebugMessageLabel"
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.fromScale(0.5, 0.92)
messageLabel.Size = UDim2.fromScale(0.5, 0.05)
messageLabel.BackgroundTransparency = 0.3
messageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
messageLabel.TextColor3 = Color3.new(1, 1, 0)
messageLabel.TextScaled = true
messageLabel.Font = Enum.Font.GothamBold
messageLabel.Text = ""
messageLabel.Visible = false
messageLabel.Parent = screenGui

local messageToken = 0

QueueDebugMessageEvent.OnClientEvent:Connect(function(message: string)
	messageToken += 1
	local currentToken = messageToken
	messageLabel.Text = "[Queue] " .. message
	messageLabel.Visible = true
	task.delay(MESSAGE_DURATION_SECONDS, function()
		if messageToken == currentToken then
			messageLabel.Visible = false
		end
	end)
end)
