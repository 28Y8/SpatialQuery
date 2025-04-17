# Spatial Query
A utility class for spatial queries in Roblox. If you do not want to use Knit, then just use your own Signal module or take the signal module from [Knit/RbxUtil](https://sleitnick.github.io/RbxUtil/api/Signal/).

# Features:
*    Find closest parts, models, or tagged objects
*    Detect objects within a radius
*    Raycasting with configurable options
*    Line of sight checking
*    Configurable search scope for performance optimization
*    Events for when closest objects change

# Public Methods:
```lua
query:GetClosestPart(position, options)
query:GetClosestModel(position, options)
query:GetClosestTagged(position, tag, options)

query:GetPartsInRadius(position, radius, options)
query:GetModelsInRadius(position, radius, options)
query:GetTaggedInRadius(position, radius, tag, options)

query:GetPreviousClosestPart()
query:GetPreviousClosestModel()
```

# Example:
```lua
local query = SpatialQuery.new(game.Workspace.Level)  -- Search only in Level folder

query.OnClosestPartChanged:Connect(function(newPart, oldPart)
    print("Closest part changed from", oldPart, "to", newPart)
end)

local closestPart = query:GetClosestPart(origin, {
    maxDistance = 100,
    ignoreList = {character},
    predicate = function(part) return part.Name == "Target" end,
    lineOfSightRequired = true
})
```
