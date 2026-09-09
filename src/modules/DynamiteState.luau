--!strict
-- Estado del equipo vaquero para el sabotaje "dinamita": cargas disponibles
-- y fin del cooldown compartido de equipo. Autoridad exclusiva del servidor.

local RunService = game:GetService("RunService")

local DynamiteState = {}

local MAX_CHARGES = 3

local charges = 0
local cooldownEndsAt = 0
local changedCallbacks: { () -> () } = {}

local function isServer(): boolean
	return RunService:IsServer()
end

local function fireChanged()
	for _, callback in ipairs(changedCallbacks) do
		callback()
	end
end

function DynamiteState.OnChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end

function DynamiteState.ResetCharges()
	if not isServer() then
		warn("DynamiteState.ResetCharges must be called from the server")
		return
	end
	charges = 0
	cooldownEndsAt = 0
	fireChanged()
end

function DynamiteState.AddCharge()
	if not isServer() then
		warn("DynamiteState.AddCharge must be called from the server")
		return
	end
	if charges >= MAX_CHARGES then
		return
	end
	charges += 1
	fireChanged()
end

function DynamiteState.GetCharges(): number
	return charges
end

function DynamiteState.GetCooldownEndsAt(): number
	return cooldownEndsAt
end

function DynamiteState.TrySpendCharge(cooldownSeconds: number, serverTimeNow: number): boolean
	if not isServer() then
		warn("DynamiteState.TrySpendCharge must be called from the server")
		return false
	end
	if charges <= 0 or serverTimeNow < cooldownEndsAt then
		return false
	end
	charges -= 1
	cooldownEndsAt = serverTimeNow + cooldownSeconds
	fireChanged()
	return true
end

return DynamiteState
