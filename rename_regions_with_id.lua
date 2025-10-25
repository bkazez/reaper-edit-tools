-- Rename Regions with ID
-- Description: Renames each region to "{region name} {region ID}"
-- Author: Claude
-- Version: 1.0

local function getProjectMarkerCount()
  local markerCount, regionCount = reaper.CountProjectMarkers(0)
  return markerCount + regionCount
end

local function renameRegionsWithID()
  local totalMarkers = getProjectMarkerCount()
  local regionsRenamed = 0

  for i = 0, totalMarkers - 1 do
    local retval, isRegion, pos, rgnend, name, markrgnindexnumber, color = reaper.EnumProjectMarkers3(0, i)

    if retval > 0 and isRegion then
      local regionID = markrgnindexnumber
      local newName = string.format("%s %d", name, regionID)

      -- Only rename if the format isn't already applied
      if not string.match(name, "%s%d+$") or name ~= newName then
        reaper.SetProjectMarker3(0, markrgnindexnumber, isRegion, pos, rgnend, newName, color)
        regionsRenamed = regionsRenamed + 1
      end
    end
  end

  return regionsRenamed
end

local function main()
  local projectRegionCount = select(2, reaper.CountProjectMarkers(0))

  if projectRegionCount == 0 then
    reaper.ShowMessageBox("No regions found in project.", "Rename Regions with ID", 0)
    return
  end

  reaper.Undo_BeginBlock()

  local regionsRenamed = renameRegionsWithID()

  reaper.Undo_EndBlock("Rename regions with ID", -1)

  reaper.ShowMessageBox(string.format("Renamed %d region(s).", regionsRenamed), "Rename Regions with ID", 0)
end

main()
