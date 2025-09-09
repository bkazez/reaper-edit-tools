-- reaper-edit-tools
-- Convert Proxies to Multitrack: Converts selected proxy items back to multitrack audio based on regions
-- Author: Ben Kazez
-- GitHub: https://github.com/bkazez/reaper-edit-tools

function removeFileExtension(filename)
    return filename:match("(.+)%..+") or filename
end

function findRegion(name)
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, isRegion, pos, rgnend, regionName = reaper.EnumProjectMarkers(i)
        if isRegion and regionName == name then
            return pos, rgnend
        end
    end
    return nil
end

function getRegionItems(regionStart, regionEnd)
    local items = {}
    for trackIdx = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, trackIdx)
        for itemIdx = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, itemIdx)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local itemEnd = pos + length
            
            -- Find items that overlap with the region
            if itemEnd > regionStart and pos < regionEnd then
                items[#items + 1] = {
                    track = track,
                    item = item,
                    pos = pos,
                    length = length
                }
            end
        end
    end
    return items
end

function copyFades(from, to)
    -- Copy all fade/crossfade properties
    local fadeProps = {
        "D_FADEINLEN", "D_FADEINSHAPE", "D_FADEINLEN_AUTO", 
        "D_FADEOUTLEN", "D_FADEOUTSHAPE", "D_FADEOUTLEN_AUTO",
        "C_FADEINSHAPE", "C_FADEOUTSHAPE"
    }
    
    for _, prop in ipairs(fadeProps) do
        local value = reaper.GetMediaItemInfo_Value(from, prop)
        reaper.SetMediaItemInfo_Value(to, prop, value)
    end
end

function copyOriginalPropsToNewItem(fromOriginalItem, toNewItem)
    -- Copy all properties from original multitrack items (vol, mute, loop, lock)
    -- Proxy items are used purely for editing decisions, not for mixing values
    local itemProps = {"D_VOL", "B_MUTE", "B_LOOPSRC", "C_LOCK"}
    for _, prop in ipairs(itemProps) do
        local value = reaper.GetMediaItemInfo_Value(fromOriginalItem, prop)
        reaper.SetMediaItemInfo_Value(toNewItem, prop, value)
    end
    
    -- Copy item title/name
    local _, itemName = reaper.GetSetMediaItemInfo_String(fromOriginalItem, "P_NOTES", "", false)
    if itemName and itemName ~= "" then
        reaper.GetSetMediaItemInfo_String(toNewItem, "P_NOTES", itemName, true)
    end
end

function createMultitrack(proxyItem)
    local proxyTake = reaper.GetActiveTake(proxyItem)
    if not proxyTake then return false, "No take" end
    
    local _, takeName = reaper.GetSetMediaItemTakeInfo_String(proxyTake, "P_NAME", "", false)
    local regionName = removeFileExtension(takeName)
    local regionStart, regionEnd = findRegion(regionName)
    if not regionStart then return false, "Region '" .. regionName .. "' not found" end
    
    local proxyPos = reaper.GetMediaItemInfo_Value(proxyItem, "D_POSITION")
    local proxyLength = reaper.GetMediaItemInfo_Value(proxyItem, "D_LENGTH")
    
    -- Get the source offset from the proxy to know which part of the region it represents
    local proxySourceOffset = reaper.GetMediaItemTakeInfo_Value(proxyTake, "D_STARTOFFS")
    local regionSourceStart = regionStart + proxySourceOffset
    local regionSourceEnd = regionSourceStart + proxyLength
    
    local regionItems = getRegionItems(regionStart, regionEnd)
    if #regionItems == 0 then return false, "No items in region" end
    
    local created = 0
    for _, data in ipairs(regionItems) do
        local take = reaper.GetActiveTake(data.item)
        if take then
            local itemEnd = data.pos + data.length
            
            -- Check if this region item overlaps with our desired slice
            if itemEnd > regionSourceStart and data.pos < regionSourceEnd then
                local sliceStart = math.max(data.pos, regionSourceStart)
                local sliceEnd = math.min(itemEnd, regionSourceEnd)
                
                if sliceStart < sliceEnd then
                    local sliceLength = sliceEnd - sliceStart
                    local offsetInProxy = sliceStart - regionSourceStart
                    
                    local item = reaper.AddMediaItemToTrack(data.track)
                    reaper.SetMediaItemInfo_Value(item, "D_POSITION", proxyPos + offsetInProxy)
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", sliceLength)
                    
                    local newTake = reaper.AddTakeToMediaItem(item)
                    reaper.SetMediaItemTake_Source(newTake, reaper.GetMediaItemTake_Source(take))
                    
                    local origOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", origOffset + sliceStart - data.pos)
                    
                    -- Copy play rate from proxy item
                    local proxyPlayRate = reaper.GetMediaItemTakeInfo_Value(proxyTake, "D_PLAYRATE")
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", proxyPlayRate)
                    
                    -- Copy take name from original item
                    local _, originalTakeName = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                    if originalTakeName and originalTakeName ~= "" then
                        reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", originalTakeName, true)
                    end
                    
                    copyOriginalPropsToNewItem(data.item, item)
                    copyFades(proxyItem, item)
                    created = created + 1
                end
            end
        end
    end
    
    return true, created .. " items created from '" .. regionName .. "'"
end

function main()
    local selected = reaper.CountSelectedMediaItems(0)
    if selected == 0 then
        reaper.ShowMessageBox("Select proxy items to convert", "No Selection", 0)
        return
    end
    
    reaper.Undo_BeginBlock()
    local success, errors = 0, {}
    
    for i = 0, selected - 1 do
        local ok, msg = createMultitrack(reaper.GetSelectedMediaItem(0, i))
        if ok then
            success = success + 1
        else
            errors[#errors + 1] = "Item " .. (i + 1) .. ": " .. msg
        end
    end
    
    reaper.UpdateArrange()
    
    local result = success .. " of " .. selected .. " proxies converted"
    if #errors > 0 then result = result .. "\nErrors:\n• " .. table.concat(errors, "\n• ") end
    reaper.ShowMessageBox(result, "Convert Complete", 0)
    
    reaper.Undo_EndBlock("Convert Proxies to Multitrack", -1)
end

main()