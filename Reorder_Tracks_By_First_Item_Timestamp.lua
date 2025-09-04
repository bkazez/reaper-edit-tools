-- Reorder Visible Tracks by First Media Item Timestamp
-- REAPER script to reorder visible tracks based on timestamp of first media item in each track

function getFirstItemPosition(track)
    local numItems = reaper.GetTrackNumMediaItems(track)
    if numItems == 0 then
        return nil -- No items on this track
    end
    
    local earliestPos = math.huge
    for i = 0, numItems - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if itemPos < earliestPos then
            earliestPos = itemPos
        end
    end
    
    return earliestPos
end

function getSelectedTracks()
    local selectedTracks = {}
    local numTracks = reaper.CountTracks(0)
    
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then
            table.insert(selectedTracks, track)
        end
    end
    
    return selectedTracks
end

function getTracksWithTimestamps()
    local tracksWithItems = {}
    local selectedTracks = getSelectedTracks()
    local tracksToProcess
    
    -- Use selected tracks if any are selected, otherwise use all tracks
    if #selectedTracks > 0 then
        tracksToProcess = selectedTracks
    else
        tracksToProcess = {}
        local numTracks = reaper.CountTracks(0)
        for i = 0, numTracks - 1 do
            table.insert(tracksToProcess, reaper.GetTrack(0, i))
        end
    end
    
    -- Process the tracks to get those with items and timestamps
    for _, track in ipairs(tracksToProcess) do
        local firstItemPos = getFirstItemPosition(track)
        if firstItemPos then
            table.insert(tracksWithItems, {
                track = track,
                originalIndex = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1,
                firstItemPos = firstItemPos
            })
        end
    end
    
    return tracksWithItems
end

function main()
    reaper.Undo_BeginBlock()
    
    -- Check if we're working with selected tracks or all tracks
    local selectedTracks = getSelectedTracks()
    local workingWithSelected = #selectedTracks > 0
    
    -- Get tracks with their first item timestamps
    local tracksWithItems = getTracksWithTimestamps()
    
    if #tracksWithItems == 0 then
        local message = workingWithSelected and "No selected tracks with media items found" or "No tracks with media items found"
        reaper.ShowMessageBox(message, "Info", 0)
        reaper.Undo_EndBlock("Reorder tracks by timestamp", -1)
        return
    end
    
    -- Sort tracks by first item position (timestamp)
    table.sort(tracksWithItems, function(a, b)
        return a.firstItemPos < b.firstItemPos
    end)
    
    -- Clear all track selections first
    reaper.SetOnlyTrackSelected(reaper.GetTrack(0, 0))
    reaper.SetTrackSelected(reaper.GetTrack(0, 0), false)
    
    -- Reorder tracks by selecting and moving them
    local targetPos = 0
    for _, trackData in ipairs(tracksWithItems) do
        local track = trackData.track
        local currentTrackNum = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1 -- Convert to 0-based
        
        -- Select only this track
        reaper.SetOnlyTrackSelected(track)
        
        -- Move track to correct position
        if currentTrackNum > targetPos then
            -- Move track up
            local moves = currentTrackNum - targetPos
            for i = 1, moves do
                reaper.ReorderSelectedTracks(targetPos, 0)
            end
        elseif currentTrackNum < targetPos then
            -- Move track down
            local moves = targetPos - currentTrackNum
            for i = 1, moves do
                reaper.ReorderSelectedTracks(targetPos, 1)
            end
        end
        
        targetPos = targetPos + 1
    end
    
    -- Clear selections
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(track, false)
    end
    
    -- Update display
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
    
    local message = string.format("Reordered %d %s by first media item timestamp", 
        #tracksWithItems,
        workingWithSelected and "selected tracks" or "tracks"
    )
    reaper.ShowMessageBox(message, "Complete", 0)
    
    reaper.Undo_EndBlock("Reorder tracks by timestamp", -1)
end

-- Run the script
main()