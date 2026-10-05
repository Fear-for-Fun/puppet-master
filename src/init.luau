export type PerformanceSettings = {
	maxFrameRate: number?, -- fps when within nearDistance (default 30)
	minFrameRate: number?, -- absolute floor, used when far away or in a big crowd (default 3)
	nearDistance: number?, -- inside this distance the puppet updates at maxFrameRate (default 20)
	farDistance: number?, -- at/after this distance the puppet updates at minFrameRate (default 150)
	falloffExponent: number?, -- 1 = linear falloff, >1 stays fast longer, <1 drops faster (default 1)
}

export type CrowdSettings = {
	startCount: number, -- puppet count where scaling begins
	fullCount: number, -- puppet count where scaling reaches minScale
	minScale: number, -- rate multiplier at fullCount (0.25 = quarter speed)
}
