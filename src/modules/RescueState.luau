--!strict
-- Estado de las "cuerdas de rescate" compartidas por equipo: cargas
-- disponibles para evitar que un jugador derribado quede esperando
-- checkpoint. Mismo patron que DynamiteState.luau (autoridad exclusiva del
-- servidor), pero parametrizado por track porque, a diferencia de la
-- dinamita, aplica simetricamente a ambos equipos.

local RunService = game:GetService("RunService")

local RescueState = {}

local STARTING_CORDS = 3

local cordsByTrack: { [string]: number } = {
	Track_A = STARTING_CORDS,
	Track_B = STARTING_CORDS,
}

local changedCallbacks: { () -> () } = {}

local function isServer(): boolean
	return RunService:IsServer()
end

local function fireChanged()
	for _, callback in ipairs(changedCallbacks) do
		callback()
	end
end

function RescueState.OnChanged(callback: () -> ())
	table.insert(changedCallbacks, callback)
end

function RescueState.ResetCords()
	if not isServer() then
		warn("RescueState.ResetCords must be called from the server")
		return
	end
	cordsByTrack.Track_A = STARTING_CORDS
	cordsByTrack.Track_B = STARTING_CORDS
	fireChanged()
end

function RescueState.GetCords(trackName: string): number
	return cordsByTrack[trackName] or 0
end

function RescueState.TrySpendCord(trackName: string): boolean
	if not isServer() then
		warn("RescueState.TrySpendCord must be called from the server")
		return false
	end
	local current = cordsByTrack[trackName]
	if not current or current <= 0 then
		return false
	end
	cordsByTrack[trackName] = current - 1
	fireChanged()
	return true
end

return RescueState
