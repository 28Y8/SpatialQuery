--[[

	A utility class for spatial queries in Roblox.
    
	Features:
	- Find closest parts, models, or tagged objects
	- Detect objects within a radius
	- Raycasting with configurable options
	- Line of sight checking
	- Proximity filtering with custom conditions
	- Configurable search scope for performance optimization
	- Events for when closest objects change

	Example usage:
	
	local query = SpatialQuery.new(game.Workspace.Level) -- Search only in Level folder

	query.OnClosestPartChanged:Connect(function(newPart, oldPart)
	    print("Closest part changed from", oldPart, "to", newPart)
	end)
	
	local closestPart = query:GetClosestPart(originVector3, {
    	maxDistance = 100,
	    ignoreList = {game.Workspace.Tree},
	    lineOfSightRequired = true
	})
	
]]

---- Services ----

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

---- Modules ----

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(Knit.Util.Signal)

---- Class ---

local SpatialQuery = {}
SpatialQuery.__index = SpatialQuery

---- Constants ---

local DEFAULT_MAX_DISTANCE = 100
local DEFAULT_RAYCAST_DISTANCE = 1000

---- Functions ---

--[[
    Create a new SpatialQuery instance
    @param searchScope Instance - The root instance to search within (defaults to workspace)
    @return SpatialQuery - The new instance
]]
function SpatialQuery.new(searchScope)
	local self = setmetatable({}, SpatialQuery)

	self.searchScope = searchScope or game.Workspace

	self.previousResults = {
		closestPart = nil,
		closestModel = nil,
		closestTagged = {},
		closestNamed = {},
	}

	-- Cache for descendants to avoid repeated calls
	self.descendantsCache = nil

	-- Events
	self.OnClosestPartChanged = Signal.new()
	self.OnClosestModelChanged = Signal.new()
	self.OnClosestTaggedChanged = Signal.new()

	return self
end

---- Methods ---

--[[
    Set a new search scope for this instance
    @param searchScope Instance - The new root instance to search within
    @return self - For method chaining
]]
function SpatialQuery:SetSearchScope(searchScope)
	if self.searchScope ~= searchScope then
		self.searchScope = searchScope or game.Workspace

		-- Clear the cache since scope changed
		self.descendantsCache = nil
	end

	return self
end

--[[
    Get all descendants in the current search scope (with caching)
    @param forceRefresh boolean - Whether to force a refresh of the cache
    @return table - Array of all descendants
]]
function SpatialQuery:GetAllDescendants(forceRefresh)
	if forceRefresh or not self.descendantsCache then
		self.descendantsCache = self.searchScope:GetDescendants()
	end

	return self.descendantsCache
end

--[[
    Clear the descendants cache to free memory or ensure fresh results
    @return self - For method chaining
]]
function SpatialQuery:ClearCache()
	self.descendantsCache = nil

	return self
end

--[[
    Find the closest part to the given position
    @param position Vector3 - Origin position for the search
    @param options table - Configuration options:
        - maxDistance (number): Maximum search distance
        - ignoreList (table): Instances to ignore
        - predicate (function): Optional filter function(part) that returns true to include the part
        - searchScope (Instance): Optional override for search scope just for this query
        - useCache (boolean): Whether to use cached descendants (true by default)
        - lineOfSightRequired (boolean): Whether line of sight is required (false by default)
    @return BasePart, number - The closest part and its distance, or nil if none found
]]
function SpatialQuery:GetClosestPart(position, options)
	options = options or {}

	local maxDistance = options.maxDistance or DEFAULT_MAX_DISTANCE
	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local searchScope = options.searchScope or self.searchScope
	local useCache = options.useCache
	local lineOfSightRequired = options.lineOfSightRequired or false

	if useCache == nil then
		useCache = true
	end

	-- If search scope is different from current, we can't use cache
	if searchScope ~= self.searchScope then
		useCache = false
	end

	local closestPart = nil
	local closestDistance = maxDistance

	-- Get all parts in the search scope
	local descendants

	if searchScope == self.searchScope and useCache then
		descendants = self:GetAllDescendants()
	else
		descendants = searchScope:GetDescendants()
	end

	local validParts = {}

	for _, descendant in ipairs(descendants) do
		-- Check if it's a BasePart
		if descendant:IsA("BasePart") then
			-- Skip if in ignore list
			local shouldIgnore = false

			for _, ignored in ipairs(ignoreList) do
				if descendant == ignored or descendant:IsDescendantOf(ignored) then
					shouldIgnore = true

					break
				end
			end

			if not shouldIgnore then
				-- Check if it meets custom predicate
				local meetsPredicate = true

				if predicate then
					meetsPredicate = predicate(descendant)
				end

				if meetsPredicate then
					local distance = (position - descendant.Position).Magnitude

					if distance < closestDistance then
						-- Check line of sight if required
						local hasLineOfSight = true

						if lineOfSightRequired then
							hasLineOfSight = self:HasLineOfSight(position, descendant.Position, {
								ignoreList = ignoreList
							})
						end

						if hasLineOfSight then
							closestPart = descendant
							closestDistance = distance
						end
					end
				end
			end
		end
	end

	-- Fire event if the closest part has changed
	if closestPart ~= self.previousResults.closestPart then
		self.OnClosestPartChanged:Fire(closestPart, self.previousResults.closestPart)
		self.previousResults.closestPart = closestPart
	end

	if closestPart then
		return closestPart, closestDistance
	end

	return nil, nil
end

--[[
    Find the closest model to the given position
    @param position Vector3 - Origin position for the search
    @param options table - Configuration options:
        - maxDistance (number): Maximum search distance
        - ignoreList (table): Instances to ignore
        - predicate (function): Optional filter function(model) that returns true to include the model
        - requirePrimaryPart (boolean): Whether models must have a PrimaryPart (true by default)
        - searchScope (Instance): Optional override for search scope just for this query
        - useCache (boolean): Whether to use cached descendants (true by default)
        - lineOfSightRequired (boolean): Whether line of sight is required (false by default)
    @return Model, number - The closest model and its distance, or nil if none found
]]
function SpatialQuery:GetClosestModel(position, options)
	options = options or {}

	local maxDistance = options.maxDistance or DEFAULT_MAX_DISTANCE
	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local requirePrimaryPart = options.requirePrimaryPart
	local searchScope = options.searchScope or self.searchScope
	local useCache = options.useCache
	local lineOfSightRequired = options.lineOfSightRequired or false

	if useCache == nil then
		useCache = true
	end

	-- If search scope is different from current, we can't use cache
	if searchScope ~= self.searchScope then
		useCache = false
	end

	if requirePrimaryPart == nil then
		requirePrimaryPart = true
	end

	local closestModel = nil
	local closestDistance = maxDistance

	-- Get all models in the search scope
	local allModels = {}

	local descendants
	if searchScope == self.searchScope and useCache then
		descendants = self:GetAllDescendants()
	else
		descendants = searchScope:GetDescendants()
	end

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("Model") then
			table.insert(allModels, descendant)
		end
	end

	for _, model in ipairs(allModels) do
		-- Skip if in ignore list
		local shouldIgnore = false

		for _, ignored in ipairs(ignoreList) do
			if model == ignored or model:IsDescendantOf(ignored) then
				shouldIgnore = true
				break
			end
		end

		if not shouldIgnore then
			-- Check if model has PrimaryPart if required
			if (not requirePrimaryPart) or model.PrimaryPart then
				-- Determine model position
				local modelPosition

				if model.PrimaryPart then
					modelPosition = model.PrimaryPart.Position
				else
					-- Use GetBoundingBox instead of calculating average position
					local success, boundingBox = pcall(function()
						return model:GetBoundingBox()
					end)

					if success then
						-- The position is in the CFrame
						modelPosition = boundingBox.Position
					else
						-- Fallback to original method if GetBoundingBox fails
						local sum = Vector3.new(0, 0, 0)
						local count = 0

						for _, child in ipairs(model:GetDescendants()) do
							if child:IsA("BasePart") then
								sum = sum + child.Position
								count = count + 1
							end
						end

						if count > 0 then
							modelPosition = sum / count
						else
							-- No parts found, skip this model
							continue
						end
					end
				end

				-- Check if it meets custom predicate
				local meetsPredicate = true

				if predicate then
					meetsPredicate = predicate(model)
				end

				if meetsPredicate then
					local distance = (position - modelPosition).Magnitude

					if distance < closestDistance then
						-- Check line of sight if required
						local hasLineOfSight = true

						if lineOfSightRequired then
							hasLineOfSight = self:HasLineOfSight(position, modelPosition, {
								ignoreList = ignoreList
							})
						end

						if hasLineOfSight then
							closestModel = model
							closestDistance = distance
						end
					end
				end
			end
		end
	end

	-- Fire event if the closest model has changed
	if closestModel ~= self.previousResults.closestModel then
		self.OnClosestModelChanged:Fire(closestModel, self.previousResults.closestModel)
		self.previousResults.closestModel = closestModel
	end

	if closestModel then
		return closestModel, closestDistance
	end

	return nil, nil
end

--[[
    Find the closest model to the given position, using a custom path to a reference part
    @param position Vector3 - Origin position for the search
    @param partPath string - Path to the reference part relative to each model (e.g. "Head" or "Tech.Monitor")
    @param options table - Configuration options:
        - maxDistance (number): Maximum search distance
        - ignoreList (table): Instances to ignore
        - predicate (function): Optional filter function(model) that returns true to include the model
        - searchScope (Instance): Optional override for search scope just for this query
        - useCache (boolean): Whether to use cached descendants (true by default)
        - lineOfSightRequired (boolean): Whether line of sight is required (false by default)
        - fallbackToDefault (boolean): Whether to fallback to PrimaryPart or bounding box if path not found (true by default)
    @return Model, number - The closest model and its distance, or nil if none found
]]
function SpatialQuery:GetClosestModelWithCustomPart(position, partPath, options)
	options = options or {}

	local maxDistance = options.maxDistance or DEFAULT_MAX_DISTANCE
	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local searchScope = options.searchScope or self.searchScope
	local useCache = options.useCache
	local lineOfSightRequired = options.lineOfSightRequired or false
	local fallbackToDefault = (options.fallbackToDefault ~= false) -- Default to true

	if useCache == nil then
		useCache = true
	end

	-- If search scope is different from current, we can't use cache
	if searchScope ~= self.searchScope then
		useCache = false
	end

	local closestModel = nil
	local closestDistance = maxDistance

	-- Get all models in the search scope
	local allModels = {}

	local descendants
	if searchScope == self.searchScope and useCache then
		descendants = self:GetAllDescendants()
	else
		descendants = searchScope:GetDescendants()
	end

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("Model") then
			table.insert(allModels, descendant)
		end
	end

	for _, model in ipairs(allModels) do
		-- Skip if in ignore list
		local shouldIgnore = false

		for _, ignored in ipairs(ignoreList) do
			if model == ignored or model:IsDescendantOf(ignored) then
				shouldIgnore = true

				break
			end
		end

		if not shouldIgnore then
			-- Check if it meets custom predicate
			local meetsPredicate = true

			if predicate then
				meetsPredicate = predicate(model)
			end

			if meetsPredicate then
				-- Try to find the custom part using the path
				local modelPosition
				local customPart
				local pathParts = {}

				-- Split the path string by periods
				for part in string.gmatch(partPath, "[^%.]+") do
					table.insert(pathParts, part)
				end

				-- Navigate through the path
				local current = model
				local pathValid = true

				for _, pathPart in ipairs(pathParts) do
					if current:FindFirstChild(pathPart) then
						current = current:FindFirstChild(pathPart)
					else
						pathValid = false
						break
					end
				end

				if pathValid and current:IsA("BasePart") then
					customPart = current
					modelPosition = customPart.Position
				elseif fallbackToDefault then
					-- Fallback to default methods if custom path not found
					if model.PrimaryPart then
						modelPosition = model.PrimaryPart.Position
					else
						-- Use GetBoundingBox for better performance
						local success, boundingBox = pcall(function()
							return model:GetBoundingBox()
						end)

						if success then
							modelPosition = boundingBox.Position
						else
							-- Fallback to original method if GetBoundingBox fails
							local sum = Vector3.new(0, 0, 0)
							local count = 0

							for _, child in ipairs(model:GetDescendants()) do
								if child:IsA("BasePart") then
									sum = sum + child.Position
									count = count + 1
								end
							end

							if count > 0 then
								modelPosition = sum / count
							else
								-- No parts found, skip this model
								continue
							end
						end
					end
				else
					-- Skip if we couldn't find the custom part and not using fallback
					continue
				end

				local distance = (position - modelPosition).Magnitude

				if distance < closestDistance then
					-- Check line of sight if required
					local hasLineOfSight = true

					if lineOfSightRequired then
						hasLineOfSight = self:HasLineOfSight(position, modelPosition, {
							ignoreList = ignoreList
						})
					end

					if hasLineOfSight then
						closestModel = model
						closestDistance = distance
					end
				end
			end
		end
	end

	-- Fire event if the closest model has changed
	if closestModel ~= self.previousResults.closestModel then
		self.OnClosestModelChanged:Fire(closestModel, self.previousResults.closestModel)

		self.previousResults.closestModel = closestModel
	end

	if closestModel then
		return closestModel, closestDistance
	end

	return nil, nil
end

-- New method to get previous closest part
function SpatialQuery:GetPreviousClosestPart()
	return self.previousResults.closestPart
end

-- New method to get previous closest model
function SpatialQuery:GetPreviousClosestModel()
	return self.previousResults.closestModel
end

--[[
    Find all parts within a given radius
    @param position Vector3 - Origin position for the search
    @param radius number - Search radius
    @param options table - Configuration options:
        - ignoreList (table): Instances to ignore
        - predicate (function): Optional filter function(part) returns true to include the part
        - maxResults (number): Maximum number of results to return
        - sortResults (boolean): Whether to sort results by distance (true by default)
        - searchScope (Instance): Optional override for search scope just for this query
        - useCache (boolean): Whether to use cached descendants (true by default)
        - lineOfSightRequired (boolean): Whether line of sight is required (false by default)
    @return table - Array of parts within radius
]]
function SpatialQuery:GetPartsInRadius(position, radius, options)
	options = options or {}

	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local maxResults = options.maxResults
	local sortResults = options.sortResults
	local searchScope = options.searchScope or self.searchScope
	local useCache = options.useCache
	local lineOfSightRequired = options.lineOfSightRequired or false

	if useCache == nil then
		useCache = true
	end

	-- If search scope is different from current, we can't use cache
	if searchScope ~= self.searchScope then
		useCache = false
	end

	if sortResults == nil then
		sortResults = true
	end

	local resultParts = {}

	-- Get all parts in the search scope
	local descendants

	if searchScope == self.searchScope and useCache then
		descendants = self:GetAllDescendants()
	else
		descendants = searchScope:GetDescendants()
	end

	for _, descendant in ipairs(descendants) do
		-- Check if it's a BasePart
		if descendant:IsA("BasePart") then
			-- Skip if in ignore list
			local shouldIgnore = false

			for _, ignored in ipairs(ignoreList) do
				if descendant == ignored or descendant:IsDescendantOf(ignored) then
					shouldIgnore = true
					break
				end
			end

			if not shouldIgnore then
				-- Check if it meets custom predicate
				local meetsPredicate = true

				if predicate then
					meetsPredicate = predicate(descendant)
				end

				if meetsPredicate then
					local distance = (position - descendant.Position).Magnitude

					if distance <= radius then
						-- Check line of sight if required
						local hasLineOfSight = true

						if lineOfSightRequired then
							hasLineOfSight = self:HasLineOfSight(position, descendant.Position, {
								ignoreList = ignoreList
							})
						end

						if hasLineOfSight then
							table.insert(resultParts, {
								part = descendant,
								distance = distance
							})
						end
					end
				end
			end
		end
	end

	-- Sort by distance if requested
	if sortResults then
		table.sort(resultParts, function(a, b)
			return a.distance < b.distance
		end)
	end

	-- Limit results if maxResults is specified
	if maxResults and #resultParts > maxResults then
		local limitedResults = {}

		for i = 1, maxResults do
			table.insert(limitedResults, resultParts[i])
		end

		resultParts = limitedResults
	end

	-- Convert to the expected format
	local results = {}

	for _, result in ipairs(resultParts) do
		table.insert(results, result.part)
	end

	return results
end

--[[
    Find all models within a given radius
    @param position Vector3 - Origin position for the search
    @param radius number - Search radius
    @param options table - Configuration options:
        - ignoreList (table): Instances to ignore
        - predicate (function): Optional filter function(model) returns true to include the model
        - requirePrimaryPart (boolean): Whether models must have a PrimaryPart
        - maxResults (number): Maximum number of results to return
        - sortResults (boolean): Whether to sort results by distance
        - searchScope (Instance): Optional override for search scope just for this query
        - useCache (boolean): Whether to use cached descendants (true by default)
        - lineOfSightRequired (boolean): Whether line of sight is required (false by default)
    @return table - Array of models within radius
]]
function SpatialQuery:GetModelsInRadius(position, radius, options)
	options = options or {}

	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local requirePrimaryPart = options.requirePrimaryPart
	local searchScope = options.searchScope or self.searchScope
	local useCache = options.useCache
	local lineOfSightRequired = options.lineOfSightRequired or false

	if useCache == nil then
		useCache = true
	end

	-- If search scope is different from current, we can't use cache
	if searchScope ~= self.searchScope then
		useCache = false
	end

	if requirePrimaryPart == nil then
		requirePrimaryPart = true
	end

	local maxResults = options.maxResults
	local sortResults = options.sortResults

	if sortResults == nil then
		sortResults = true
	end

	local resultModels = {}

	-- Get all models in the search scope
	local allModels = {}

	local descendants
	if searchScope == self.searchScope and useCache then
		descendants = self:GetAllDescendants()
	else
		descendants = searchScope:GetDescendants()
	end

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("Model") then
			table.insert(allModels, descendant)
		end
	end

	for _, model in ipairs(allModels) do
		-- Skip if in ignore list
		local shouldIgnore = false

		for _, ignored in ipairs(ignoreList) do
			if model == ignored or model:IsDescendantOf(ignored) then
				shouldIgnore = true

				break
			end
		end

		if not shouldIgnore then
			-- Check if model has PrimaryPart if required
			if (not requirePrimaryPart) or model.PrimaryPart then
				-- Determine model position
				local modelPosition

				if model.PrimaryPart then
					modelPosition = model.PrimaryPart.Position
				else
					-- Use GetBoundingBox instead of calculating average position
					local success, boundingBox = pcall(function()
						return model:GetBoundingBox()
					end)

					if success then
						-- The position is in the CFrame
						modelPosition = boundingBox.Position
					else
						-- Fallback to original method if GetBoundingBox fails
						local sum = Vector3.new(0, 0, 0)
						local count = 0

						for _, child in ipairs(model:GetDescendants()) do
							if child:IsA("BasePart") then
								sum = sum + child.Position
								count = count + 1
							end
						end

						if count > 0 then
							modelPosition = sum / count
						else
							-- No parts found, skip this model
							continue
						end
					end
				end

				-- Check if it meets custom predicate
				local meetsPredicate = true

				if predicate then
					meetsPredicate = predicate(model)
				end

				if meetsPredicate then
					local distance = (position - modelPosition).Magnitude

					if distance <= radius then
						-- Check line of sight if required
						local hasLineOfSight = true

						if lineOfSightRequired then
							hasLineOfSight = self:HasLineOfSight(position, modelPosition, {
								ignoreList = ignoreList
							})
						end

						if hasLineOfSight then
							table.insert(resultModels, {
								model = model,
								distance = distance
							})
						end
					end
				end
			end
		end
	end

	-- Sort by distance if requested
	if sortResults then
		table.sort(resultModels, function(a, b)
			return a.distance < b.distance
		end)
	end

	-- Limit results if maxResults is specified
	if maxResults and #resultModels > maxResults then
		local limitedResults = {}

		for i = 1, maxResults do
			table.insert(limitedResults, resultModels[i])
		end

		resultModels = limitedResults
	end

	-- Convert to the expected format
	local results = {}

	for _, result in ipairs(resultModels) do
		table.insert(results, result.model)
	end

	return results
end

--[[
    Find tagged objects within a radius
    @param position Vector3 - Origin position for the search
    @param radius number - Search radius
    @param tag string - CollectionService tag to search for
    @param options table - Configuration options (same as GetPartsInRadius/GetModelsInRadius)
    @return table - Array of tagged objects within radius
]]
function SpatialQuery:GetTaggedInRadius(position, radius, tag, options)
	options = options or {}

	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local maxResults = options.maxResults
	local sortResults = options.sortResults
	local searchScope = options.searchScope or self.searchScope
	local lineOfSightRequired = options.lineOfSightRequired or false

	if sortResults == nil then
		sortResults = true
	end

	local resultObjects = {}

	-- Get all objects with the specified tag
	-- Note: We'll still need to filter by searchScope
	local taggedObjects = CollectionService:GetTagged(tag)

	for _, object in ipairs(taggedObjects) do
		-- Skip objects not in our search scope
		if not (object == searchScope or object:IsDescendantOf(searchScope)) then
			continue
		end

		-- Skip if in ignore list
		local shouldIgnore = false

		for _, ignored in ipairs(ignoreList) do
			if object == ignored or object:IsDescendantOf(ignored) then
				shouldIgnore = true
				break
			end
		end

		if not shouldIgnore then
			-- Determine object position
			local objectPosition

			if object:IsA("BasePart") then
				objectPosition = object.Position
			elseif object:IsA("Model") and object.PrimaryPart then
				objectPosition = object.PrimaryPart.Position
			elseif object:IsA("Model") then
				-- Use GetBoundingBox instead of calculating average position
				local success, boundingBox = pcall(function()
					return object:GetBoundingBox()
				end)

				if success then
					-- The position is in the CFrame
					objectPosition = boundingBox.Position
				else
					-- Fallback to original method if GetBoundingBox fails
					local sum = Vector3.new(0, 0, 0)
					local count = 0

					for _, child in ipairs(object:GetDescendants()) do
						if child:IsA("BasePart") then
							sum = sum + child.Position
							count = count + 1
						end
					end

					if count > 0 then
						objectPosition = sum / count
					else
						-- No parts found, skip this object
						continue
					end
				end
			else
				-- Use average position of all parts
				local sum = Vector3.new(0, 0, 0)
				local count = 0

				for _, child in ipairs(object:GetDescendants()) do
					if child:IsA("BasePart") then
						sum = sum + child.Position
						count = count + 1
					end
				end

				if count > 0 then
					objectPosition = sum / count
				else
					-- No parts found, skip this object
					continue
				end
			end

			-- Check if it meets custom predicate
			local meetsPredicate = true

			if predicate then
				meetsPredicate = predicate(object)
			end

			if meetsPredicate then
				local distance = (position - objectPosition).Magnitude

				if distance <= radius then
					-- Check line of sight if required
					local hasLineOfSight = true

					if lineOfSightRequired then
						hasLineOfSight = self:HasLineOfSight(position, objectPosition, {
							ignoreList = ignoreList
						})
					end

					if hasLineOfSight then
						table.insert(resultObjects, {
							object = object,
							distance = distance
						})
					end
				end
			end
		end
	end

	-- Sort by distance if requested
	if sortResults then
		table.sort(resultObjects, function(a, b)
			return a.distance < b.distance
		end)
	end

	-- Limit results if maxResults is specified
	if maxResults and #resultObjects > maxResults then
		local limitedResults = {}

		for i = 1, maxResults do
			table.insert(limitedResults, resultObjects[i])
		end

		resultObjects = limitedResults
	end

	-- Convert to the expected format
	local results = {}

	for _, result in ipairs(resultObjects) do
		table.insert(results, result.object)
	end

	return results
end

--[[
    Find the closest tagged object
    @param position Vector3 - Origin position for the search
    @param tag string - CollectionService tag to search for
    @param options table - Configuration options (similar to other closest methods)
    @return Instance, number - The closest tagged object and its distance, or nil if none found
]]
function SpatialQuery:GetClosestTagged(position, tag, options)
	options = options or {}

	local maxDistance = options.maxDistance or DEFAULT_MAX_DISTANCE
	local ignoreList = options.ignoreList or {}
	local predicate = options.predicate
	local searchScope = options.searchScope or self.searchScope
	local lineOfSightRequired = options.lineOfSightRequired or false

	local closestObject = nil
	local closestDistance = maxDistance

	-- Get all objects with the specified tag
	local taggedObjects = CollectionService:GetTagged(tag)

	for _, object in ipairs(taggedObjects) do
		-- Skip objects not in our search scope
		if not (object == searchScope or object:IsDescendantOf(searchScope)) then
			continue
		end

		-- Skip if in ignore list
		local shouldIgnore = false

		for _, ignored in ipairs(ignoreList) do
			if object == ignored or object:IsDescendantOf(ignored) then
				shouldIgnore = true
				break
			end
		end

		if not shouldIgnore then
			-- Determine object position
			local objectPosition

			if object:IsA("BasePart") then
				objectPosition = object.Position
			elseif object:IsA("Model") and object.PrimaryPart then
				objectPosition = object.PrimaryPart.Position
			elseif object:IsA("Model") then
				-- Use GetBoundingBox instead of calculating average position
				local success, boundingBox = pcall(function()
					return object:GetBoundingBox()
				end)

				if success then
					-- The position is in the CFrame
					objectPosition = boundingBox.Position
				else
					-- Fallback to original method if GetBoundingBox fails
					local sum = Vector3.new(0, 0, 0)
					local count = 0

					for _, child in ipairs(object:GetDescendants()) do
						if child:IsA("BasePart") then
							sum = sum + child.Position
							count = count + 1
						end
					end

					if count > 0 then
						objectPosition = sum / count
					else
						-- No parts found, skip this object
						continue
					end
				end
			else
				-- Use average position of all parts
				local sum = Vector3.new(0, 0, 0)
				local count = 0

				for _, child in ipairs(object:GetDescendants()) do
					if child:IsA("BasePart") then
						sum = sum + child.Position
						count = count + 1
					end
				end

				if count > 0 then
					objectPosition = sum / count
				else
					-- No parts found, skip this object
					continue
				end
			end

			-- Check if it meets custom predicate
			local meetsPredicate = true
			if predicate then
				meetsPredicate = predicate(object)
			end

			if meetsPredicate then
				local distance = (position - objectPosition).Magnitude

				if distance < closestDistance then
					-- Check line of sight if required
					local hasLineOfSight = true

					if lineOfSightRequired then
						hasLineOfSight = self:HasLineOfSight(position, objectPosition, {
							ignoreList = ignoreList
						})
					end

					if hasLineOfSight then
						closestObject = object
						closestDistance = distance
					end
				end
			end
		end
	end

	-- Fire event if closest tagged object changed
	local tagKey = "closestTagged_" .. tag

	if closestObject ~= self.previousResults.closestTagged[tag] then
		self.OnClosestTaggedChanged:Fire(tag, closestObject, self.previousResults.closestTagged[tag])

		self.previousResults.closestTagged[tag] = closestObject
	end

	if closestObject then
		return closestObject, closestDistance
	end

	return nil, nil
end

--[[
    Check if there's a line of sight between two positions
    @param fromPosition Vector3 - Starting position
    @param toPosition Vector3 - Target position
    @param options table - Configuration options:
        - ignoreList (table): Instances to ignore in the raycast
        - ignoreWater (boolean): Whether to ignore water in the raycast
    @return boolean - True if there's line of sight, false otherwise
]]
function SpatialQuery:HasLineOfSight(fromPosition, toPosition, options)
	options = options or {}

	local ignoreList = options.ignoreList or {}
	local ignoreWater = options.ignoreWater or false

	local direction = toPosition - fromPosition
	local distance = direction.Magnitude
	local unitDirection = direction.Unit

	-- Create RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.IgnoreWater = ignoreWater

	-- Perform raycast
	local result = workspace:Raycast(fromPosition, direction, raycastParams)

	-- No hit means clear line of sight
	if not result then
		return true
	end

	-- Hit something, but check how far
	local hitDistance = (result.Position - fromPosition).Magnitude

	-- If hit distance is very close to target distance, we consider it a line of sight
	-- This helps with floating point imprecision
	local epsilon = 0.1

	return math.abs(hitDistance - distance) < epsilon
end

--[[
    Cast a ray and get detailed results
    @param origin Vector3 - Ray origin position
    @param direction Vector3 - Ray direction (will be normalized and scaled by maxDistance)
    @param options table - Configuration options:
        - maxDistance (number): Maximum ray distance
        - ignoreList (table): Instances to ignore
        - ignoreWater (boolean): Whether to ignore water
        - respectCanCollide (boolean): Whether to respect CanCollide property
    @return RaycastResult - Roblox raycast result or nil if nothing hit
]]
function SpatialQuery:Raycast(origin, direction, options)
	options = options or {}

	local maxDistance = options.maxDistance or DEFAULT_RAYCAST_DISTANCE
	local ignoreList = options.ignoreList or {}
	local ignoreWater = options.ignoreWater or false
	local respectCanCollide = options.respectCanCollide

	-- Normalize and scale direction
	local scaledDirection = direction.Unit * maxDistance

	-- Create RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.IgnoreWater = ignoreWater

	if respectCanCollide ~= nil then
		raycastParams.RespectCanCollide = respectCanCollide
	end

	-- Perform raycast
	return game.Workspace:Raycast(origin, scaledDirection, raycastParams)
end

--[[
    Get the closest position on the NavMesh from a given position
    @param position Vector3 - The position to find the closest NavMesh point from
    @param options table - Configuration options:
        - maxDistance (number): Maximum search distance
    @return Vector3 - The closest position on the NavMesh, or nil if none found
]]
function SpatialQuery:GetClosestNavMeshPosition(position, options)
	-- Lazy load PathfindingService
	local PathfindingService = game:GetService("PathfindingService")

	options = options or {}
	local maxDistance = options.maxDistance or DEFAULT_MAX_DISTANCE

	-- Try to find the closest point on the NavMesh
	local success, result = pcall(function()
		return PathfindingService:FindNearestValidPosition(position, maxDistance)
	end)

	if success then
		return result
	end

	return nil
end

--[[
    Check if a position is within the NavMesh
    @param position Vector3 - The position to check
    @return boolean - True if the position is on the NavMesh, false otherwise
]]
function SpatialQuery:IsPositionOnNavMesh(position)
	local closestPosition = self:GetClosestNavMeshPosition(position, {maxDistance = 0.1})

	if closestPosition then
		return (position - closestPosition).Magnitude < 0.1
	end

	return false
end

--[[
    Find object by name pattern (using string.find)
    @param pattern string - The pattern to search for
    @param options table - Configuration options:
        - parent (Instance): Parent to search within (default: searchScope)
        - recursive (boolean): Whether to search recursively (default: true)
        - caseSensitive (boolean): Whether search is case sensitive (default: false)
        - maxResults (number): Maximum number of results to return
        - useCache (boolean): Whether to use cached descendants (true by default)
    @return table - Array of found objects
]]
function SpatialQuery:FindByNamePattern(pattern, options)
	options = options or {}

	local parent = options.parent or self.searchScope
	local recursive = options.recursive
	local useCache = options.useCache

	if useCache == nil then
		useCache = true
	end

	-- If parent is different from search scope, we can't use cache
	if parent ~= self.searchScope then
		useCache = false
	end

	if recursive == nil then
		recursive = true
	end

	local caseSensitive = options.caseSensitive or false
	local maxResults = options.maxResults

	local results = {}

	-- Pattern flags
	local flags = caseSensitive and "" or "i"

	-- Function to search children
	if recursive then
		local descendants

		if parent == self.searchScope and useCache then
			descendants = self:GetAllDescendants()
		else
			descendants = parent:GetDescendants()
		end

		for _, descendant in ipairs(descendants) do
			-- Check if name matches pattern
			if string.find(descendant.Name, pattern, 1, false, flags) then
				table.insert(results, descendant)

				-- Stop if we've reached max results
				if maxResults and #results >= maxResults then
					break
				end
			end
		end
	else
		-- Just search immediate children
		local children = parent:GetChildren()

		for _, child in ipairs(children) do
			-- Check if name matches pattern
			if string.find(child.Name, pattern, 1, false, flags) then
				table.insert(results, child)

				-- Stop if we've reached max results
				if maxResults and #results >= maxResults then
					break
				end
			end
		end
	end

	return results
end

--[[
    Find objects by name that match a given pattern
    @param pattern string - The pattern to match against object names
    @param options table - Configuration options
    @return table - Array of found objects
]]
function SpatialQuery:FindObjectsByName(pattern, options)
	options = options or {}

	local parent = options.parent or self.searchScope
	local recursive = options.recursive ~= false  -- Default to true
	local maxResults = options.maxResults
	local exactMatch = options.exactMatch or false
	local caseSensitive = options.caseSensitive or false

	local results = {}

	-- Function to check if a name matches the pattern
	local function nameMatches(name)
		if exactMatch then
			if caseSensitive then
				return name == pattern
			else
				return string.lower(name) == string.lower(pattern)
			end
		else
			if caseSensitive then
				return string.find(name, pattern, 1, true) ~= nil
			else
				return string.find(string.lower(name), string.lower(pattern), 1, true) ~= nil
			end
		end
	end

	-- Function to process an object
	local function processObject(obj)
		if nameMatches(obj.Name) then
			table.insert(results, obj)

			-- Check if we've reached the maximum results
			if maxResults and #results >= maxResults then
				return true -- Stop processing
			end
		end

		return false -- Continue processing
	end

	-- Search recursively or just immediate children
	if recursive then
		for _, descendant in ipairs(parent:GetDescendants()) do
			if processObject(descendant) then
				break
			end
		end
	else
		for _, child in ipairs(parent:GetChildren()) do
			if processObject(child) then
				break
			end
		end
	end

	-- Track closest named object if requested
	if options.trackClosest and options.position then
		local closestObject = nil
		local closestDistance = math.huge

		for _, obj in ipairs(results) do
			local objectPosition

			if obj:IsA("BasePart") then
				objectPosition = obj.Position
			elseif obj:IsA("Model") and obj.PrimaryPart then
				objectPosition = obj.PrimaryPart.Position
			else
				continue
			end

			local distance = (options.position - objectPosition).Magnitude

			if distance < closestDistance then
				closestObject = obj
				closestDistance = distance
			end
		end

		-- Fire event if closest named object changed
		local nameKey = "closestNamed_" .. pattern

		if closestObject ~= self.previousResults.closestNamed[nameKey] then
			self.ClosestNamedObjectChanged:Fire(pattern, closestObject, self.previousResults.closestNamed[nameKey])
			self.previousResults.closestNamed[nameKey] = closestObject
		end
	end

	return results
end

--[[
    Clean up the SpatialQuery instance and remove all event connections
    @return nil
]]
function SpatialQuery:Destroy()
	-- Disconnect all signals
	self.OnClosestPartChanged:Destroy()
	self.OnClosestModelChanged:Destroy()
	self.OnClosestTaggedChanged:Destroy()

	-- Clear signals
	self.OnClosestPartChanged = nil
	self.OnClosestModelChanged = nil
	self.OnClosestTaggedChanged = nil

	-- Clear caches and state
	self.descendantsCache = nil
	self.previousResults = nil
	self.searchScope = nil

	-- Clear metatable
	setmetatable(self, nil)
end

---- Return ---

return SpatialQuery
