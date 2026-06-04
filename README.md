# Puppet Master

Puppet Master is a simple front-end module that allows objects (`puppet`) to smoothly interpolate to another object or a (`master`) This module can be useful for setting up smooth client visuals without making a huge mess.

# Good Use Cases:
- Make a player's pet float around their head and do a spin every few seconds
- Have AI models replicated on the client as a `puppet` that follows the server's `master` part
- Shoot a magic projectile straight forwards and have a puppet make a wavy trail behind it

<img width="540" height="540" alt="puppetMasterIcon" src="https://github.com/user-attachments/assets/f6eefab5-dccf-407f-80d7-a5ba7c999e5b" />

## Usage
To construct a PuppetMaster class, you'll need a `master: Model | BasePart` a `puppet: Model | BasePart` and optionally settings `settings: Settings`

After constructing a `PuppetMaster` with `.new()`, you can freely `:Play(runtimeSignal: RBXScriptConnection?)` or `:Pause()` the connection.

- By default the connection uses a `RunService.PostSimulation` signal, but this can be customized by sending a signal through the `runtimeSignal: RBXScriptConnection?` parameter in `:Play(runtimeSignal: RBXScriptConnection?)`

### Example
```lua
local PuppetMaster = PuppetMaster.new(masterPart, puppetPart, {
		style = PuppetMaster.StyleModules.Linear, -- what style the puppet follows the master in (use PuppetMaster.StyleModules in the settings)
		turnSpeed = 20, -- gets / 100 and used as the alpha during lookVector interpolation
		lerpSpeed = 5, -- gets / 100 and used as the alpha during position interpolation
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
local idleOffset = testPuppet:AddOffset(Vector3.yAxis * 4, 1, false)

PuppetMaster:Play(RunService.Heartbeat)
```
