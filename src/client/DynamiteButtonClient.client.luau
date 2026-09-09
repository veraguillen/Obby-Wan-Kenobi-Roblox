--!strict
-- Boton de sabotaje "dinamita" para el equipo vaquero (Track_B): visible
-- solo mientras el jugador tiene AssignedTrack == Track_B. Muestra cargas
-- disponibles y, si esta en cooldown de equipo, la cuenta regresiva.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DynamiteActivateEvent = RemoteEvents:WaitForChild("DynamiteActivateEvent") :: RemoteEvent
local DynamiteStatusEvent = RemoteEvents:WaitForChild("DynamiteStatusEvent") :: RemoteEvent
local DynamiteMessageEvent = RemoteEvents:WaitForChild("DynamiteMessageEvent") :: RemoteEvent

local MESSAGE_DURATION_SECONDS = 2

local SABOTEUR_TRACK = "Track_B"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DynamiteButtonGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "DynamiteButton"
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.fromScale(0.98, 0.95)
button.Size = UDim2.fromScale(0.16, 0.07)
button.BackgroundColor3 = Color3.new(0.6, 0.1, 0.1)
button.TextColor3 = Color3.new(1, 1, 1)
button.TextScaled = true
button.Font = Enum.Font.GothamBold
button.Text = "DINAMITA"
button.Parent = screenGui

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "DynamiteMessageLabel"
messageLabel.AnchorPoint = Vector2.new(1, 1)
messageLabel.Position = UDim2.fromScale(0.98, 0.86)
messageLabel.Size = UDim2.fromScale(0.3, 0.06)
messageLabel.BackgroundTransparency = 0.3
messageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
messageLabel.TextColor3 = Color3.new(1, 1, 1)
messageLabel.TextScaled = true
messageLabel.Font = Enum.Font.GothamBold
messageLabel.Text = ""
messageLabel.Visible = false
messageLabel.Parent = screenGui

local messageToken = 0

local currentCharges = 0
local cooldownEndsAt = 0
local hasHadChargeAvailable = false

local function refreshButtonText()
	local remainingCooldown = cooldownEndsAt - Workspace:GetServerTimeNow()
	if remainingCooldown > 0 then
		button.Text = string.format("DINAMITA (%ds)", math.ceil(remainingCooldown))
	else
		button.Text = string.format("DINAMITA (%d)", currentCharges)
	end
end

local function updateVisibility()
	if currentCharges > 0 then
		hasHadChargeAvailable = true
	end
	screenGui.Enabled = player:GetAttribute("AssignedTrack") == SABOTEUR_TRACK and hasHadChargeAvailable
end

player:GetAttributeChangedSignal("AssignedTrack"):Connect(updateVisibility)
updateVisibility()

DynamiteStatusEvent.OnClientEvent:Connect(function(charges: number, cooldownEndsAtServerTime: number)
	currentCharges = charges
	cooldownEndsAt = cooldownEndsAtServerTime
	refreshButtonText()
	updateVisibility()
end)

DynamiteMessageEvent.OnClientEvent:Connect(function(message: string)
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

task.spawn(function()
	while true do
		if screenGui.Enabled then
			refreshButtonText()
		end
		task.wait(0.5)
	end
end)

button.Activated:Connect(function()
	local remainingCooldown = cooldownEndsAt - Workspace:GetServerTimeNow()
	if currentCharges <= 0 or remainingCooldown > 0 then
		return
	end
	DynamiteActivateEvent:FireServer()
end)
