--!strict
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PuppetMaster = {}
PuppetMaster.__index = PuppetMaster

local stylesFolder = script.styles
PuppetMaster.StyleModules = {
	Linear = { name = "Linear", module = require(stylesFolder.linear) },
	Spring = { name = "Spring", module = require(stylesFolder.spring) },
}

export type StyleModules = { name: string, module: ModuleScript }

local getPuppetRotation = require(script["get-rotation"])

export type StyleModuleSettings = (
	self: PuppetMaster,
	masterCFrame: CFrame,
	puppetCFrame: CFrame,
	lerpSpeed: number,
	distance: number,
	delta: Vector3?
) -> Vector3

export type SpringSettings = {
	speed: number?,
	fadeIn: number?,
	strength: number?,
}
export type Settings = {
	style: StyleModules | any?,
	lerpSpeed: number?,
	turnSpeed: number?,
	lookVectorClamping: Vector2?,
	snapThreshold: number?,

	springSettings: SpringSettings?,

	debug: {
		debugTrails: boolean?,
	}?,
}

export type PuppetMaster = typeof(setmetatable(
	{} :: {
		master: Instance,
		puppet: Instance,

		offsetObjects: { { Obj: Vector3Value, Priority: number } },
		offsetTweenConnections: { [Vector3Value]: RBXScriptConnection },

		--[[
			-- lookVectorClamping: Vector2 --
			numbers range from 0 to 1.
			1 - looks fully to focusTarget
			0.5 - can look 180 degrees forward from where master is looking
			0 - looks fully where master is looking

			X - applies to horizontal axis
			Y - applies to vertical axis
		]]
		lookVectorClamping: Vector2,

		focusTarget: Instance, -- puppet will look at this instance, when nil puppet follows the masters lookDir

		style: StyleModules | any?, -- what style the puppet follows the master in (use PuppetMaster.StyleModules in the settings)
		turnSpeed: number, -- gets / 100 and used as the alpha during lookVector interpolation
		lerpSpeed: number, -- gets / 100 and used as the alpha during poosition interpolation
		snapThreshold: number, -- the maximum distance before the puppet copies the master's position instead of interpolating

		-- // specific variables for styles
		springSpeed: number, -- used for Spring style only, affects the frequency of waves
		springFadeIn: number, -- level of gradual decline of spring strength when close to master
		springStrength: number, -- maximum vertex

		debug: {
			debugTrails: boolean?,
			debugInstances: { Instance },
		}?,

		runTimeConnection: RBXScriptConnection,
	},
	PuppetMaster
))

--[=[
	```lua
	local PuppetMaster = PuppetMaster.new(masterPart, puppetPart, {
		style = PuppetMaster.StyleModules.Linear,
		turnSpeed = 20,
		lerpSpeed = 5,
		lookVectorClamping = Vector2.new(1, 0.2),
		snapThreshold = 0.01,

		springSettings = {
			speed = 15,
			fadeIn = 4,
			strength = 1,
		},

		debug = {
			debugTrails = false,
		},
	})
	```
]=]
function PuppetMaster.new(master: Instance, puppet: Instance, settings: Settings?): PuppetMaster
	local self = setmetatable({}, PuppetMaster) :: PuppetMaster

	self.master = master
	self.puppet = puppet

	self.offsetObjects = {}
	self.offsetTweenConnections = {}

	settings = settings or {} :: Settings
	self.snapThreshold = settings and settings.snapThreshold or 0.01
	self.lerpSpeed = settings and settings.lerpSpeed or 10
	self.turnSpeed = settings and settings.turnSpeed or 10
	self.lookVectorClamping = settings and settings.lookVectorClamping or Vector2.new(1, 1)
	self.style = settings and settings.style or PuppetMaster.StyleModules.Linear

	local springSettings = settings and settings.springSettings or {} :: SpringSettings
	self.springSpeed = springSettings and springSettings.speed or 10
	self.springFadeIn = springSettings and springSettings.fadeIn or 4
	self.springStrength = springSettings and springSettings.strength or 2

	self.debug = settings and (settings.debug :: any) or nil

	if self.debug then
		self.debug.debugInstances = {}
	end

	if self.debug and self.debug.debugTrails then
		(self :: any):_createDebugTrail(master, Color3.fromRGB(0, 255, 0));
		(self :: any):_createDebugTrail(puppet, Color3.fromRGB(255, 0, 0))
	end

	return self
end

function PuppetMaster.Play(self: PuppetMaster, runtimeSignal: RBXScriptSignal?)
	local signal = runtimeSignal or RunService.PostSimulation

	self.runTimeConnection = signal:Connect(function()
		self:Runtime()
	end)
end

function PuppetMaster.Runtime(self: PuppetMaster)
	local focusTarget = self.focusTarget

	local masterCFrame = #self.offsetObjects > 0
			and self:_applyAllOffsets(self:_getInstanceCFrame(self.master) :: CFrame)
		or self:_getInstanceCFrame(self.master) :: CFrame

	local puppetCFrame = self:_getInstanceCFrame(self.puppet) :: CFrame
	local focusTargetCFrame = focusTarget and self:_getInstanceCFrame(focusTarget) :: CFrame or nil

	local masterPosition, puppetPosition = masterCFrame.Position, (puppetCFrame :: CFrame).Position

	if not masterPosition or not puppetCFrame then
		return
	end

	local delta = masterPosition - puppetPosition
	local distance = delta.Magnitude
	local lerpSpeed = self.lerpSpeed / 100
	local turnSpeed = self.turnSpeed / 100

	local styleMod = self.style and self.style.module

	if styleMod then
		local styledPos = styleMod(self, masterCFrame, puppetCFrame, lerpSpeed, distance, delta)

		local desiredLook = focusTargetCFrame and (focusTargetCFrame.Position - styledPos).Unit or nil
		local puppetRotation =
			getPuppetRotation(masterCFrame, puppetCFrame, desiredLook, self.lookVectorClamping, turnSpeed)

		local finalCFrame = CFrame.new(styledPos) * puppetRotation
		self:_setInstanceCFrame(self.puppet, finalCFrame)
	else
		self:_setInstanceCFrame(self.puppet, CFrame.new(masterPosition) * puppetCFrame.Rotation)
	end
end

function PuppetMaster.Pause(self: PuppetMaster)
	if self.runTimeConnection then
		self.runTimeConnection:Disconnect()
	end

	for _, val in self.offsetTweenConnections do
		val:Disconnect()
	end

	table.clear(self.offsetTweenConnections)

	if self.debug then
		for _, inst: Instance in self.debug.debugInstances do
			inst:Destroy()
		end
	end
end

function PuppetMaster.AddFocusTarget(self: PuppetMaster, target: BasePart | Model)
	self.focusTarget = target
end

function PuppetMaster.AddOffset(
	self: PuppetMaster,
	offset: Vector3,
	priority: number,
	clearOffsets: boolean
): Vector3Value?
	if not offset then
		return
	end

	local newObj = Instance.new("Vector3Value")
	newObj.Value = offset

	if clearOffsets then
		self:ClearOffsets()
	end

	table.insert(self.offsetObjects, { Obj = newObj, Priority = priority })

	return newObj
end

function PuppetMaster.ClearOffsets(self: PuppetMaster)
	if not self.offsetObjects[1] then
		return
	end

	for _, data in self.offsetObjects do
		data.Obj:Destroy()
	end

	table.clear(self.offsetObjects)
end

function PuppetMaster.TweenOffset(
	self: PuppetMaster,
	offset: Vector3,
	priority: number,
	clearOffsets: boolean,
	tweenInfo: TweenInfo
)
	if not offset then
		return
	end

	tweenInfo = tweenInfo or TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true)

	local newObj = Instance.new("Vector3Value")
	newObj.Value = Vector3.zero

	if clearOffsets then
		self:ClearOffsets()
	end

	local tbl = { Obj = newObj, Priority = priority }
	table.insert(self.offsetObjects, tbl)

	local tween = TweenService:Create(newObj, tweenInfo, {
		Value = offset,
	})

	tween:Play()

	self.offsetTweenConnections[newObj] = tween.Completed:Once(function()
		table.remove(self.offsetObjects, table.find(self.offsetObjects, tbl))
		self.offsetTweenConnections[newObj] = nil
		newObj:Destroy()
	end)
end

function PuppetMaster.Destroy(self: PuppetMaster)
	self:Pause()

	for _, data in self.offsetObjects do
		local obj = data.Obj
		if not obj or not obj.Parent then
			continue
		end

		obj:Destroy()
	end

	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

function PuppetMaster._applyAllOffsets(self: PuppetMaster, cframe: CFrame): CFrame?
	if not cframe then
		return
	end

	local newCFrame = cframe

	table.sort(self.offsetObjects, function(a, b)
		return a.Priority < b.Priority
	end)

	for _, offsetData: { Obj: Vector3Value, Priority: number } in self.offsetObjects do
		newCFrame = CFrame.new(offsetData.Obj.Value + newCFrame.Position) * newCFrame.Rotation
	end

	return newCFrame
end

local function checkInstanceError(isModel: boolean, isBasePart: boolean, instance: Instance)
	if not isBasePart and not isModel then
		warn(instance)
		error(`Given instance: '{instance}' cannot read a position`, 2)
	end
end

function PuppetMaster._getInstancePosition(_: PuppetMaster, instance: any): Vector3?
	local isModel, isBasePart = instance:IsA("Model"), instance:IsA("BasePart")
	checkInstanceError(isModel, isBasePart, instance)

	if isModel then
		local primaryPart = instance.PrimaryPart
		return primaryPart and primaryPart.Position or instance:GetPivot().Position
	end

	return (instance :: BasePart).Position
end

function PuppetMaster._getInstanceCFrame(_: PuppetMaster, instance: any): CFrame?
	local isModel, isBasePart = instance:IsA("Model"), instance:IsA("BasePart")
	checkInstanceError(isModel, isBasePart, instance)

	if isModel then
		local primaryPart = instance.PrimaryPart
		return primaryPart and primaryPart.CFrame or instance:GetPivot()
	end

	return (instance :: BasePart).CFrame
end

function PuppetMaster._setInstanceCFrame(_: PuppetMaster, instance: any, cframe: CFrame)
	local isModel, isBasePart = instance:IsA("Model"), instance:IsA("BasePart")
	checkInstanceError(isModel, isBasePart, instance)

	if isModel and instance.PrimaryPart then
		instance.PrimaryPart.CFrame = cframe
	elseif isModel then
		instance:PivotTo(cframe)
	end

	instance.CFrame = cframe
end

local ATTACH_0 = Instance.new("Attachment")
ATTACH_0.Name = "TrailAttachment0"
ATTACH_0.Position = Vector3.new(0, 0.05, 0)

local ATTACH_1 = Instance.new("Attachment")
ATTACH_1.Name = "TrailAttachment1"
ATTACH_1.Position = Vector3.new(0, -0.05, 0)

local TRAIL = Instance.new("Trail")
TRAIL.Name = "PuppetMasterDebugTrail"
TRAIL.Lifetime = 2
TRAIL.MinLength = 0.01
TRAIL.WidthScale = NumberSequence.new(2.5)
TRAIL.FaceCamera = true

function PuppetMaster._createDebugTrail(self: PuppetMaster, instance: Instance, color: Color3)
	local debugInstances = self.debug and self.debug.debugInstances
	if not debugInstances then
		return
	end

	local attachmentParent: BasePart?

	if instance:IsA("BasePart") then
		attachmentParent = instance
	elseif instance:IsA("Model") then
		attachmentParent = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end

	if not attachmentParent then
		return
	end

	if attachmentParent:FindFirstChild("PuppetMasterDebugTrail") then
		return
	end

	local attachment0 = ATTACH_0:Clone()
	attachment0.Parent = attachmentParent

	local attachment1 = ATTACH_1:Clone()
	attachment1.Parent = attachmentParent

	local trail = TRAIL:Clone()
	trail.Color = ColorSequence.new(color)
	trail.Parent = attachmentParent

	debugInstances[#debugInstances + 1] = attachment0
	debugInstances[#debugInstances + 1] = attachment1
	debugInstances[#debugInstances + 1] = trail
end

return PuppetMaster
