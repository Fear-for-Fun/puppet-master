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

PuppetMaster.CrowdSettings = {
	startCount = 35,
	fullCount = 100,
	minScale = 0.05,
} :: CrowdSettings

PuppetMaster.PerformanceEnabled = true

local BASE_FPS = 30
local totalPlaying = 0

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

export type PerformanceSettings = {
	enabled: boolean?, -- false = update every step, ignoring all throttling (default true)
	maxFrameRate: number?,
	minFrameRate: number?,
	nearDistance: number?,
	farDistance: number?,
	falloffExponent: number?,
}

export type CrowdSettings = {
	startCount: number, -- puppet count where scaling begins
	fullCount: number, -- puppet count where scaling reaches minScale
	minScale: number, -- rate multiplier at fullCount (0.25 = quarter speed)
}

export type SpringSettings = {
	speed: number?,
	fadeIn: number?,
	strength: number?,
}
export type OffsetSettings = {
	RelativeTo: "World" | "Master" | "Focus",
	AvoidClipping: boolean,
	ClippingOffset: number,
	Priority: number,
	OffsetFocusOrientation: boolean,
	ClippingParams: RaycastParams?,
}

export type OffsetObject = {
	Instance: CFrameValue,
	Settings: OffsetSettings,
}

export type Settings = {
	style: StyleModules | any?,
	lerpSpeed: number?,
	turnSpeed: number?,
	lookVectorClamping: Vector2?,
	snapThreshold: number?,

	springSettings: SpringSettings?,
	performance: PerformanceSettings?,

	debug: {
		debugTrails: boolean?,
	}?,

	destroyObjectWhenParentSetsToNil: boolean?,
}

export type PuppetMaster = typeof(setmetatable(
	{} :: {
		master: Instance,
		puppet: Instance,

		offsetObjects: { OffsetObject },
		offsetTweenConnections: { [CFrameValue]: RBXScriptConnection },

		lookVectorClamping: Vector2,

		activeSignal: RBXScriptConnection?,
		lastFrameUpdate: number,
		desiredFrameRateLimit: number,
		minFrameRate: number,
		nearDistance: number,
		farDistance: number,
		falloffExponent: number,
		performanceEnabled: boolean,

		focusTarget: Instance?,

		style: StyleModules | any?, -- what style the puppet follows the master in (use PuppetMaster.StyleModules in the settings)
		turnSpeed: number, -- gets / 100 and used as the alpha during lookVector interpolation
		lerpSpeed: number, -- gets / 100 and used as the alpha during poosition interpolation
		snapThreshold: number, -- the maximum distance before the puppet copies the master's position instead of interpolating

		-- // specific variables for styles
		springSpeed: number, -- affects the frequency of waves
		springFadeIn: number, -- level of gradual decline of spring strength when close to master
		springStrength: number, -- maximum vertex

		debug: {
			debugTrails: boolean?,
			debugInstances: { Instance },
		}?,

		destroyObjectWhenParentSetsToNil: boolean,

		runTimeConnection: RBXScriptConnection,
		destroyConnections: { RBXScriptConnection },
		focusTargetDestroyConnection: RBXScriptConnection,
	},
	PuppetMaster
))

--[=[
	```lua
	local PuppetMaster = PuppetMaster.new(masterPart, puppetPart, {
		style = PuppetMaster.StyleModules.Linear, -- what style the puppet follows the master in (use PuppetMaster.StyleModules in the settings)
		turnSpeed = 20, -- gets / 100 and used as the alpha during lookVector interpolation
		lerpSpeed = 5, -- gets / 100 and used as the alpha during poosition interpolation
		snapThreshold = 0.01, -- the maximum distance before the puppet copies the master's position instead of interpolating
		
		--[[
			-- lookVectorClamping: Vector2 --
			numbers range from 0 to 1.
			1 - looks fully to focusTarget
			0.5 - can look 180 degrees forward from where master is looking
			0 - looks fully where master is looking

			X - applies to horizontal axis
			Y - applies to vertical axis
		]]
		lookVectorClamping = Vector2.new(1, 0.2),

		-- // specific variables for styles
		springSettings = {
			speed = 15, -- affects the frequency of waves
			fadeIn = 4, -- level of gradual decline of spring strength when close to master
			strength = 1, -- maximum vertex
		},

		debug = {
			debugTrails = false,
		},
	})

	-- puppet will look at this instance, when nil puppet follows the masters lookDir
	PuppetMaster:AddFocusTarget(workspace:WaitForChild("FocusTarget"))
	
	-- puppet will be offset by 4 studs above the master, function retruns Vector3Value
	local idleOffset :: CFrameValue = testPuppet:AddOffset(Vector3.yAxis * 4, 1, false)

	PuppetMaster:Play(RunService.Heartbeat)
	```
]=]

type Group = {
	connection: RBXScriptConnection,
	puppets: { [PuppetMaster]: true },
	count: number,
}

local groups: { [string]: Group } = {}
local function getCrowdScale(): number
	local crowd = PuppetMaster.CrowdSettings
	if totalPlaying <= crowd.startCount then
		return 1
	end
	local range = math.max(crowd.fullCount - crowd.startCount, 1)
	local t = math.clamp((totalPlaying - crowd.startCount) / range, 0, 1)
	return 1 - t * (1 - crowd.minScale)
end

local function getTargetFrameRate(pm: PuppetMaster, distance: number, crowdScale: number): number
	local maxFps = pm.desiredFrameRateLimit or 30
	local minFps = math.min(pm.minFrameRate, maxFps)

	local range = math.max(pm.farDistance - pm.nearDistance, 0.001)
	local alpha = math.clamp((distance - pm.nearDistance) / range, 0, 1) ^ pm.falloffExponent

	local fps = (maxFps + (minFps - maxFps) * alpha) * crowdScale
	return math.max(fps, minFps)
end

local function stepGroup(group: Group)
	debug.profilebegin("PM_Step")
	local now = os.clock()

	local globalEnabled = PuppetMaster.PerformanceEnabled
	local camera = globalEnabled and workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position
	local crowdScale = globalEnabled and getCrowdScale() or 1

	for pm in group.puppets do
		if globalEnabled and pm.performanceEnabled then
			local distance = 0
			if cameraPosition then
				local pos = pm:_getInstancePosition(pm.puppet) :: Vector3
				distance = (pos - cameraPosition).Magnitude
			end

			local fps = getTargetFrameRate(pm, distance, crowdScale)
			if now - pm.lastFrameUpdate < 1 / fps then
				continue
			end
		end

		debug.profilebegin("PM_Update")
		pm:Update(now)
		debug.profileend()
	end

	debug.profileend()
end
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

	local perf = settings and settings.performance or {} :: PerformanceSettings
	self.desiredFrameRateLimit = perf.maxFrameRate or 30
	self.minFrameRate = perf.minFrameRate or 5
	self.nearDistance = perf.nearDistance or 20
	self.farDistance = perf.farDistance or 150
	self.falloffExponent = perf.falloffExponent or 5
	self.performanceEnabled = perf.enabled ~= false

	-- stagger so puppets at low rates don't all update on the same frame
	self.lastFrameUpdate = os.clock() - math.random() / math.max(self.minFrameRate, 1)

	self.debug = settings and (settings.debug :: any) or nil

	if self.debug then
		self.debug.debugInstances = {}
	end

	if self.debug and self.debug.debugTrails then
		(self :: any):_createDebugTrail(master, Color3.fromRGB(0, 255, 0));
		(self :: any):_createDebugTrail(puppet, Color3.fromRGB(255, 0, 0))
	end

	self.destroyObjectWhenParentSetsToNil = settings and settings.destroyObjectWhenParentSetsToNil or true

	self.destroyConnections = {}
	self.destroyConnections[#self.destroyConnections + 1] = master.AncestryChanged:Connect(function()
		if not master or not master.Parent and self.destroyObjectWhenParentSetsToNil then
			self:Destroy()
		end
	end)
	self.destroyConnections[#self.destroyConnections + 1] = puppet.AncestryChanged:Connect(function()
		if not puppet or not puppet.Parent and self.destroyObjectWhenParentSetsToNil then
			self:Destroy()
		end
	end)

	return self
end

function PuppetMaster.Play(self: PuppetMaster, runtimeSignal: RBXScriptSignal?)
	if self.activeSignal then
		return -- already playing
	end

	local signal = runtimeSignal or RunService.PostSimulation
	local key = tostring(signal)

	local group = groups[key]
	if not group then
		local newGroup = { puppets = {}, count = 0 } :: any
		newGroup.connection = signal:Connect(function()
			stepGroup(newGroup)
		end)
		groups[key] = newGroup
		group = newGroup
	end

	group.puppets[self] = true
	group.count += 1
	totalPlaying += 1
	self.activeSignal = signal
end

function PuppetMaster.Update(self: PuppetMaster, now: number?)
	local focusTarget = self.focusTarget

	local currentTime = now or os.clock()
	local last = self.lastFrameUpdate
	local deltaTime = last and (currentTime - last) or (1 / BASE_FPS)
	self.lastFrameUpdate = currentTime

	local offsetMasterCFrame: CFrame?
	local afterFocusRotationOffset: CFrame = CFrame.identity

	if #self.offsetObjects > 0 then
		offsetMasterCFrame, afterFocusRotationOffset =
			self:_applyAllOffsets(self:_getInstanceCFrame(self.master) :: CFrame)
	end

	local masterCFrame = offsetMasterCFrame or self:_getInstanceCFrame(self.master) :: CFrame
	local puppetCFrame = self:_getInstanceCFrame(self.puppet) :: CFrame
	local focusTargetCFrame = focusTarget and self:_getInstanceCFrame(focusTarget) :: CFrame or nil

	local masterPosition, puppetPosition = masterCFrame.Position, (puppetCFrame :: CFrame).Position

	if not masterPosition or not puppetCFrame then
		return
	end

	self.lastFrameUpdate = os.clock()

	local delta = masterPosition - puppetPosition
	local distance = delta.Magnitude
	local lerpSpeed = self:_getframeIndependentAlpha(self.lerpSpeed / 100, deltaTime)
	local turnSpeed = self:_getframeIndependentAlpha(self.turnSpeed / 100, deltaTime)

	local styleMod = self.style and self.style.module

	if styleMod then
		local styledPos = styleMod(self, masterCFrame, puppetCFrame, lerpSpeed, distance, delta)

		local desiredLook = focusTargetCFrame and (focusTargetCFrame.Position - styledPos).Unit or nil
		local puppetRotation = getPuppetRotation(
			masterCFrame,
			puppetCFrame,
			desiredLook,
			self.lookVectorClamping,
			turnSpeed,
			afterFocusRotationOffset
		)

		local finalCFrame = CFrame.new(styledPos) * puppetRotation
		self:_setInstanceCFrame(self.puppet, finalCFrame)
	else
		self:_setInstanceCFrame(self.puppet, CFrame.new(masterPosition) * puppetCFrame.Rotation)
	end
end

function PuppetMaster.Pause(self: PuppetMaster)
	local signal = self.activeSignal
	if signal then
		local key = tostring(signal)
		local group = groups[key]

		if group then
			if group.puppets[self] then
				group.puppets[self] = nil
				group.count -= 1
				totalPlaying -= 1
			end

			-- last puppet left, so the shared connection is no longer needed
			if group.count <= 0 then
				group.connection:Disconnect()
				groups[key] = nil
			end
		end

		self.activeSignal = nil
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

function PuppetMaster.SetCrowdSettings(settings: { startCount: number?, fullCount: number?, minScale: number? })
	local crowd = PuppetMaster.CrowdSettings
	crowd.startCount = settings.startCount or crowd.startCount
	crowd.fullCount = settings.fullCount or crowd.fullCount
	crowd.minScale = settings.minScale or crowd.minScale
end

function PuppetMaster.AddFocusTarget(self: PuppetMaster, target: BasePart | Model)
	self.focusTarget = target

	self.focusTargetDestroyConnection = (self.focusTarget :: Instance).AncestryChanged:Connect(function()
		if not self.focusTarget or not self.focusTarget.Parent and self.destroyObjectWhenParentSetsToNil then
			self:RemoveFocusTarget()
		end
	end)
end

function PuppetMaster.RemoveFocusTarget(self: PuppetMaster)
	self.focusTargetDestroyConnection:Disconnect()
	self.focusTarget = nil
	if self.focusTargetDestroyConnection then
		self.focusTargetDestroyConnection:Disconnect()
		self.focusTarget = nil
	end
end

function PuppetMaster.AddOffset(
	self: PuppetMaster,
	offset: CFrame,
	offsetSettings: OffsetSettings?,
	clearOffsets: boolean?
): OffsetObject?
	if not offset then
		return
	end

	offsetSettings = self:_fixOffsetSettings(offsetSettings)

	local newObj = Instance.new("CFrameValue")
	newObj.Value = offset

	if clearOffsets then
		self:ClearOffsets()
	end

	local offsetObject = { Instance = newObj, Settings = offsetSettings :: OffsetSettings }
	table.insert(self.offsetObjects, offsetObject)

	return offsetObject
end

function PuppetMaster.ClearOffsets(self: PuppetMaster)
	if not self.offsetObjects[1] then
		return
	end

	for _, data in self.offsetObjects do
		data.Instance:Destroy()
	end

	table.clear(self.offsetObjects)
end

function PuppetMaster.TweenOffset(
	self: PuppetMaster,
	offset: CFrame,
	offsetSettings: OffsetSettings?,
	clearOffsets: boolean,
	tweenInfo: TweenInfo
)
	if not offset then
		return
	end

	offsetSettings = self:_fixOffsetSettings(offsetSettings)
	tweenInfo = tweenInfo or TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, true)

	local newObj = Instance.new("CFrameValue")
	newObj.Value = CFrame.new()

	if clearOffsets then
		self:ClearOffsets()
	end

	local tbl = { Instance = newObj, Settings = offsetSettings :: OffsetSettings }
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
	self:RemoveFocusTarget()

	for _, data in self.offsetObjects do
		local obj = data.Instance
		if not obj or not obj.Parent then
			continue
		end

		obj:Destroy()
	end

	for _, connection in self.destroyConnections do
		connection:Disconnect()
	end

	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

-- Converts an alpha tuned for REFERENCE_FPS into one that gives the same
-- result over `dt` seconds, regardless of how many frames that took.
function PuppetMaster._getframeIndependentAlpha(self: PuppetMaster, alpha: number, dt: number): number
	alpha = math.clamp(alpha, 0, 1)
	if alpha >= 1 then
		return 1
	end
	return 1 - (1 - alpha) ^ (dt * BASE_FPS)
end

function PuppetMaster._fixOffsetSettings(self: PuppetMaster, offsetSettings: OffsetSettings?): OffsetSettings
	local Settings: OffsetSettings = offsetSettings or {} :: OffsetSettings

	Settings.Priority = Settings.Priority or 1
	Settings.ClippingParams = Settings.ClippingParams or nil
	Settings.ClippingOffset = Settings.ClippingOffset or 0
	Settings.RelativeTo = Settings.RelativeTo or "World"

	if Settings.OffsetFocusOrientation == nil then
		Settings.OffsetFocusOrientation = true
	end

	if Settings.AvoidClipping == nil then
		Settings.AvoidClipping = false
	end

	return Settings
end

function PuppetMaster._applyAllOffsets(self: PuppetMaster, cframe: CFrame): (CFrame?, CFrame)
	if not cframe then
		return nil, CFrame.identity
	end

	local finalPos = cframe.Position
	local preFocusRot = cframe.Rotation
	local afterFocusRot = CFrame.identity

	table.sort(self.offsetObjects, function(a, b)
		return a.Settings.Priority < b.Settings.Priority
	end)

	for _, offsetObject: OffsetObject in self.offsetObjects do
		local offset = offsetObject.Instance.Value
		local offsetPosition = offset.Position
		local desiredPos = cframe.Position + offset.Position
		local dir = desiredPos - cframe.Position
		local mag = dir.Magnitude
		local unit = dir.Unit

		if offsetObject.Settings.AvoidClipping then
			local rayDirection = unit * (mag + offsetObject.Settings.ClippingOffset)

			local rayResult = self:_raycast(
				cframe.Position,
				rayDirection,
				offsetObject.Settings.ClippingParams,
				{ self.master, self.puppet }
			)

			if rayResult then
				local hitDistance = rayResult.Distance
				local safeDistance = math.max(hitDistance - offsetObject.Settings.ClippingOffset, 0)

				offsetPosition = unit * safeDistance
			end
		end

		local Relativity = offsetObject.Settings.RelativeTo

		if Relativity == "Master" then
			offsetPosition *= cframe.LookVector
		elseif Relativity == "Focus" then
			local directionToFocusTarget = self.focusTarget
					and (cframe.Position - (self:_getInstanceCFrame(self.focusTarget) :: CFrame).Position).Unit :: Vector3
				or Vector3.one
			offsetPosition = self.focusTarget and offsetPosition * directionToFocusTarget or offsetPosition
		end

		finalPos += offsetPosition

		if offsetObject.Settings.OffsetFocusOrientation then
			afterFocusRot *= offset.Rotation
		else
			preFocusRot *= offset.Rotation
		end
	end

	local finalMasterCFrame = CFrame.new(finalPos) * preFocusRot
	return finalMasterCFrame, afterFocusRot
end

local function checkInstanceError(isModel: boolean, isBasePart: boolean, instance: Instance)
	if not isBasePart and not isModel then
		warn(instance)
		error(`Given instance: '{instance}' cannot read a position`, 2)
	end
end

function PuppetMaster._raycast(_: PuppetMaster, origin: Vector3, direction: Vector3, rayParams: RaycastParams?, ...)
	local RaycastParams = rayParams or RaycastParams.new()
	RaycastParams.FilterDescendantsInstances = ...

	local result = workspace:Raycast(origin, direction, RaycastParams)
	return result
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
		return
	elseif isModel then
		instance:PivotTo(cframe)
		return
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
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(color)
	trail.Parent = attachmentParent

	debugInstances[#debugInstances + 1] = attachment0
	debugInstances[#debugInstances + 1] = attachment1
	debugInstances[#debugInstances + 1] = trail
end

return PuppetMaster
