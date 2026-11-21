local TaskState = {}

function TaskState.new(): { [string]: any }
	local state: { [string]: any } = {
		spawned = {},
		spawnedSet = {},

		resumeCounts = setmetatable({}, { __mode = "k" }),
	}

	local RESUME_CAP = 512

	function state.add(thread: any)
		if state.spawnedSet[thread] then
			return
		end
		state.spawned[#state.spawned + 1] = thread
		state.spawnedSet[thread] = true
	end

	function state.isSpawned(thread: any): boolean
		return state.spawnedSet[thread] == true
	end

	function state.remove(thread: any)
		state.spawnedSet[thread] = nil
		state.resumeCounts[thread] = nil
		for i = #state.spawned, 1, -1 do
			if state.spawned[i] == thread then
				table.remove(state.spawned, i)
			end
		end
	end

	function state.resumeSpawned()
		local i = 1
		while i <= #state.spawned do
			local thread = state.spawned[i]
			if coroutine.status(thread) == "suspended" then
				local count = (state.resumeCounts[thread] or 0) + 1
				state.resumeCounts[thread] = count
				if count > RESUME_CAP then

					pcall(coroutine.close, thread)
					state.remove(thread)
					continue
				end
				pcall(coroutine.resume, thread)
			end
			if coroutine.status(thread) == "dead" then
				state.remove(thread)
			else
				i += 1
			end
		end
	end

	return state
end

return TaskState
