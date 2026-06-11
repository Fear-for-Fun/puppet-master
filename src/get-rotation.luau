return function(
	masterCFrame: CFrame,
	puppetCFrame: CFrame,
	desiredLook: Vector3?,
	lookVectorClamping: Vector2,
	turnSpeed: number,
	afterFocusRotationOffset: CFrame
): CFrame
	if not desiredLook then
		return puppetCFrame.Rotation:Lerp(masterCFrame.Rotation, turnSpeed)
	end

	afterFocusRotationOffset = afterFocusRotationOffset or CFrame.identity

	local masterLook = masterCFrame.LookVector

	local masterYaw = math.atan2(-masterLook.X, -masterLook.Z)
	local desiredYaw = math.atan2(-desiredLook.X, -desiredLook.Z)

	local masterPitch = math.asin(masterLook.Y)
	local desiredPitch = math.asin(desiredLook.Y)

	local yawDelta = math.atan2(math.sin(desiredYaw - masterYaw), math.cos(desiredYaw - masterYaw))
	local pitchDelta = desiredPitch - masterPitch
	local clampedYaw = masterYaw + math.clamp(yawDelta, -lookVectorClamping.X * math.pi, lookVectorClamping.X * math.pi)

	local clampedPitch = masterPitch
		+ math.clamp(pitchDelta, -lookVectorClamping.Y * math.pi, lookVectorClamping.Y * math.pi)

	local clampedLook = Vector3.new(
		-math.sin(clampedYaw) * math.cos(clampedPitch),
		math.sin(clampedPitch),
		-math.cos(clampedYaw) * math.cos(clampedPitch)
	)

	local targetRotation = CFrame.lookAt(Vector3.zero, clampedLook).Rotation * afterFocusRotationOffset.Rotation

	return puppetCFrame.Rotation:Lerp(targetRotation, turnSpeed)
end
