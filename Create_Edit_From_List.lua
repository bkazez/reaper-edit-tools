-- Generalized Edit List Script for REAPER
-- Creates edit items from source regions based on edit list
-- Maintains multitrack sync for classical music recording
-- Run from CLI: /Applications/REAPER.app/Contents/MacOS/REAPER "project.rpp" Edit_List_Script.lua -saveas "project_edited.rpp" -close:nosave:exit

-- Configuration
local EDIT_LIST_FILE = "edit_list.txt" -- File containing edit list
local EDIT_START_OFFSET = 10 -- Seconds after last source region to start edit

-- Helper functions
function timestampToSeconds(timestamp)
    local minutes, seconds = timestamp:match("(%d+):(%d+)")
    return tonumber(minutes) * 60 + tonumber(seconds)
end

function parseTakeRange(takeStr)
    local startStr, endStr = takeStr:match("([^-]+)-([^-]+)")
    local startSeconds = timestampToSeconds(startStr)
    local endSeconds = timestampToSeconds(endStr)
    return startSeconds, endSeconds
end

function parseEditList(filename)
    local editList = {}
    local file = io.open(filename, "r")
    if not file then
        return nil, "Could not open edit list file: " .. filename
    end
    
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$") -- trim whitespace
        if line ~= "" and not line:match("^#") then -- skip empty lines and comments
            local source, timeRange = line:match("^(%S+)%s+(.+)$")
            if source and timeRange then
                table.insert(editList, {
                    source = source,
                    timeRange = timeRange
                })
            end
        end
    end
    file:close()
    
    return editList
end

function findMarkerByName(markerName)
    local numMarkers = reaper.CountProjectMarkers(0)
    for i = 0, numMarkers - 1 do
        local retval, isRegion, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if name == markerName then
            return pos, rgnend, isRegion
        end
    end
    return nil
end

function findSourceItems(sourceName, sourceStart)
    -- Find all items that correspond to the source region
    local sourceItems = {}
    local tolerance = 0.1 -- Small tolerance for position matching
    
    for trackIdx = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, trackIdx)
        local numItems = reaper.CountTrackMediaItems(track)
        
        for itemIdx = 0, numItems - 1 do
            local item = reaper.GetTrackMediaItem(track, itemIdx)
            local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            
            -- Check if item starts at source position (within tolerance)
            if math.abs(itemPos - sourceStart) < tolerance then
                table.insert(sourceItems, {
                    track = track,
                    item = item,
                    trackIdx = trackIdx
                })
            end
        end
    end
    
    return sourceItems
end

function createEditItems(sourceItems, sourceStart, editStartPos, editList)
    local currentPos = editStartPos
    
    for editIdx, edit in ipairs(editList) do
        local startSeconds, endSeconds = parseTakeRange(edit.timeRange)
        local length = endSeconds - startSeconds
        local sourceOffset = startSeconds
        
        -- Create edit item on each track that has source material
        for _, sourceData in ipairs(sourceItems) do
            local track = sourceData.track
            local originalItem = sourceData.item
            
            -- Get the take from the original source item
            local originalTake = reaper.GetActiveTake(originalItem)
            if originalTake then
                local source = reaper.GetMediaItemTake_Source(originalTake)
                
                -- Create new item for this edit segment
                local newItem = reaper.AddMediaItemToTrack(track)
                reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", currentPos)
                reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", length)
                
                -- Add take with same source as original
                local newTake = reaper.AddTakeToMediaItem(newItem)
                reaper.SetMediaItemTake_Source(newTake, source)
                
                -- Set source offset relative to the original item's offset
                local originalOffset = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_STARTOFFS")
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", originalOffset + sourceOffset)
                
                -- Copy other properties from original take
                local originalVolume = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_VOL")
                local originalPan = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_PAN")
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", originalVolume)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PAN", originalPan)
                
                -- Use exact same name as original take
                local originalTakeName = ""
                reaper.GetSetMediaItemTakeInfo_String(originalTake, "P_NAME", originalTakeName, false)
                reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", originalTakeName, true)
            end
        end
        
        -- Move to next position for next edit
        currentPos = currentPos + length
    end
    
    return currentPos
end

function findLatestSourceEnd(editList)
    local latestEnd = 0
    
    for _, edit in ipairs(editList) do
        local sourceStart, sourceEnd = findMarkerByName(edit.source)
        if sourceEnd and sourceEnd > latestEnd then
            latestEnd = sourceEnd
        elseif sourceStart then
            -- If no end marker, assume it's the start position
            if sourceStart > latestEnd then
                latestEnd = sourceStart
            end
        end
    end
    
    return latestEnd
end

-- Main execution
function main()
    reaper.Undo_BeginBlock()
    
    -- Parse edit list from file
    local editList, err = parseEditList(EDIT_LIST_FILE)
    if not editList then
        reaper.ShowMessageBox(err, "Error", 0)
        return
    end
    
    if #editList == 0 then
        reaper.ShowMessageBox("No valid entries found in edit list", "Error", 0)
        return
    end
    
    -- Group edits by source
    local sourceGroups = {}
    for _, edit in ipairs(editList) do
        if not sourceGroups[edit.source] then
            sourceGroups[edit.source] = {}
        end
        table.insert(sourceGroups[edit.source], edit)
    end
    
    -- Find the latest source region end to position the edit
    local latestSourceEnd = findLatestSourceEnd(editList)
    if latestSourceEnd == 0 then
        reaper.ShowMessageBox("Could not find any source markers in project", "Error", 0)
        return
    end
    
    -- Calculate edit start position
    local editStartPos = latestSourceEnd + EDIT_START_OFFSET
    
    -- Process each edit in order
    local currentPos = editStartPos
    local totalItems = 0
    
    for _, edit in ipairs(editList) do
        -- Find source marker
        local sourceStart, sourceEnd = findMarkerByName(edit.source)
        if not sourceStart then
            reaper.ShowMessageBox("Source marker '" .. edit.source .. "' not found in project", "Error", 0)
            return
        end
        
        -- Find all items that correspond to this source
        local sourceItems = findSourceItems(edit.source, sourceStart)
        
        if #sourceItems == 0 then
            reaper.ShowMessageBox("No items found at " .. edit.source .. " marker position", "Warning", 0)
        else
            -- Create edit items for this entry
            local startSeconds, endSeconds = parseTakeRange(edit.timeRange)
            local length = endSeconds - startSeconds
            local sourceOffset = startSeconds
            
            -- Create edit item on each track that has source material
            for _, sourceData in ipairs(sourceItems) do
                local track = sourceData.track
                local originalItem = sourceData.item
                
                -- Get the take from the original source item
                local originalTake = reaper.GetActiveTake(originalItem)
                if originalTake then
                    local source = reaper.GetMediaItemTake_Source(originalTake)
                    
                    -- Create new item for this edit segment
                    local newItem = reaper.AddMediaItemToTrack(track)
                    reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", currentPos)
                    reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", length)
                    
                    -- Disable automatic fades
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", 0)
                    
                    -- Add take with same source as original
                    local newTake = reaper.AddTakeToMediaItem(newItem)
                    reaper.SetMediaItemTake_Source(newTake, source)
                    
                    -- Set source offset relative to the original item's offset
                    local originalOffset = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_STARTOFFS")
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", originalOffset + sourceOffset)
                    
                    -- Copy other properties from original take
                    local originalVolume = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_VOL")
                    local originalPan = reaper.GetMediaItemTakeInfo_Value(originalTake, "D_PAN")
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", originalVolume)
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_PAN", originalPan)
                    
                    -- Use exact same name as original take
                    local retval, originalTakeName = reaper.GetSetMediaItemTakeInfo_String(originalTake, "P_NAME", "", false)
                    reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", originalTakeName, true)
                    
                    totalItems = totalItems + 1
                end
            end
            
            currentPos = currentPos + length
        end
    end
    
    -- Update project display
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
    
    local totalLength = currentPos - editStartPos
    local numSources = 0
    for _ in pairs(sourceGroups) do numSources = numSources + 1 end
    
    reaper.ShowMessageBox(
        string.format("Created edit from %d entries across %d sources:\n• %d total items created\n• Start position: %.2f seconds\n• Total length: %.2f seconds", 
                     #editList, numSources, totalItems, editStartPos, totalLength), 
        "Edit Complete", 0
    )
    
    reaper.Undo_EndBlock("Create Edit from List", -1)
end

-- Run the script
main()