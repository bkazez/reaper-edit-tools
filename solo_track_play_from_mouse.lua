-- Part of reaper-edit-tools
-- Solo Track Play From Mouse - Solo track under cursor and play from mouse position

function main()
    -- Get mouse position
    local window, segment, details = reaper.BR_GetMouseCursorContext()
    
    -- Check if mouse is over track controls - if so, don't do anything
    if window == "tcp" then
        return
    end
    
    -- Get track under mouse
    local track = reaper.BR_GetMouseCursorContext_Track()
    if not track then
        -- If mouse is over ruler, use topmost track
        track = reaper.GetTrack(0, 0)
        if not track then
            reaper.ShowMessageBox("No tracks in project", "Error", 0)
            return
        end
    end
    
    -- Get time position under mouse
    local mouseTime = reaper.BR_GetMouseCursorContext_Position()
    
    reaper.Undo_BeginBlock()
    
    -- Unsolo all tracks first
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local currentTrack = reaper.GetTrack(0, i)
        reaper.SetMediaTrackInfo_Value(currentTrack, "I_SOLO", 0)
    end
    
    -- Solo and select the track
    reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
    reaper.SetOnlyTrackSelected(track)
    
    -- Set play position to mouse position
    reaper.SetEditCurPos(mouseTime, true, true)
    
    -- Start playback
    reaper.OnPlayButton()
    
    reaper.Undo_EndBlock("Solo track under mouse and play from mouse position", -1)
    
    -- Update display
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
end

-- Run the script
main()