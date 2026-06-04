return function(self, masterCFrame: CFrame, puppetCFrame: CFrame, lerpSpeed: number, distance: number)
	local masterPosition = masterCFrame.Position
	local puppetPosition = puppetCFrame.Position

	local finalPosition

	if distance <= self.snapThreshold then
		finalPosition = masterPosition
	else
		finalPosition = puppetPosition:Lerp(masterPosition, lerpSpeed)
	end

	return finalPosition
end
