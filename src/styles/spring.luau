return function(self, masterCFrame: CFrame, puppetCFrame: CFrame, lerpSpeed: number, distance: number, delta: Vector3)
	local masterPosition = masterCFrame.Position
	local puppetPosition = puppetCFrame.Position

	local springSpeed = self.springSpeed
	local springFadeIn = self.springFadeIn / 4
	local springStrength = self.springStrength

	local finalPosition

	if distance <= self.snapThreshold then
		finalPosition = masterPosition
	else
		local direction = delta.Unit
		local reference = if math.abs(direction:Dot(Vector3.yAxis)) > 0.99 then Vector3.xAxis else Vector3.yAxis

		local right = direction:Cross(reference).Unit
		local up = direction:Cross(right).Unit

		local t = os.clock()

		local normalizedDistance = math.clamp((distance - self.snapThreshold) / springFadeIn, 0, 2)
		local radius = (normalizedDistance * normalizedDistance)
			* math.min(distance * (0.07 + springStrength / 100), springStrength)

		local offset = right * math.sin(t * springSpeed) * radius + up * math.cos(t * springSpeed) * radius
		local springTarget = masterPosition + offset

		finalPosition = puppetPosition:Lerp(springTarget, lerpSpeed)
	end

	return finalPosition
end
