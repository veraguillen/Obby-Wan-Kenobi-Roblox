--!strict
-- DEBUG: doble salto temporal para poder probar el recorrido de las pistas
-- sin depender del diseno final de movimiento/parkour. Borrar este archivo
-- cuando ya no haga falta.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Velocidad fija en vez de Humanoid.JumpPower: si el rig usa JumpHeight
-- (UseJumpPower = false), JumpPower puede quedar en 0 y el segundo salto
-- no se notaria.
local DOUBLE_JUMP_POWER = 50

local hasDoubleJumped = false

local function onCharacterAdded(character: Model)
	hasDoubleJumped = false
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
			hasDoubleJumped = false
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

UserInputService.JumpRequest:Connect(function()
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		return
	end

	local state = humanoid:GetState()
	local isAirborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if isAirborne and not hasDoubleJumped then
		hasDoubleJumped = true
		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, DOUBLE_JUMP_POWER, velocity.Z)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)
