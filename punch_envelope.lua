-- Punch Envelope Script
-- Creates volume automation to "punch" down the selected time region
-- with configurable fade times and punch amount

local DEFAULT_FADE_MS = 250
local ENVELOPE_SHAPE_SLOW_START_END = 2

function showPunchEnvelopeDialog()
    local retval, retvals_csv = reaper.GetUserInputs("Punch Envelope", 2, "Punch (dB):,Fade (ms):", "0," .. DEFAULT_FADE_MS)
    
    if not retval then
        return nil, nil
    end
    
    local punch_db, fade_ms = retvals_csv:match("([^,]+),([^,]+)")
    
    punch_db = tonumber(punch_db) or 0
    fade_ms = tonumber(fade_ms) or DEFAULT_FADE_MS
    
    return punch_db, fade_ms
end

function dbToEnvelopeValue(db)
    -- Let's figure out what 0.115129254 actually is mathematically
    -- From standard dB to linear conversion: 10^(db/20) 
    -- From exponential: e^(db * factor)
    -- These should be equivalent, so: 10^(db/20) = e^(db * factor)
    -- Taking ln of both sides: ln(10^(db/20)) = db * factor
    -- (db/20) * ln(10) = db * factor
    -- factor = ln(10)/20 = 2.302585.../20 = 0.115129254649...
    
    reaper.ShowConsoleMsg("Mathematical analysis:\n")
    reaper.ShowConsoleMsg("  ln(10)/20 = " .. (math.log(10)/20) .. "\n")
    reaper.ShowConsoleMsg("  X-Raym constant: 0.115129254\n")
    reaper.ShowConsoleMsg("  These match: " .. tostring(math.abs((math.log(10)/20) - 0.115129254) < 0.000001) .. "\n")
    
    -- So 0.115129254 = ln(10)/20, which converts dB to natural log scale
    local db_to_ln_factor = math.log(10) / 20  -- This IS 0.115129254...
    local base_offset = math.log(716.21785031261)
    return math.exp(base_offset + db * db_to_ln_factor)
end

function getTimeSelection()
    local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    
    if start_time == end_time then
        reaper.ShowMessageBox("No time selection found. Please select a time range.", "Error", 0)
        return nil, nil
    end
    
    return start_time, end_time
end

function getSelectedTrack()
    local track = reaper.GetSelectedTrack(0, 0)
    
    if not track then
        reaper.ShowMessageBox("No track selected. Please select a track.", "Error", 0)
        return nil
    end
    
    return track
end

function showVolumeEnvelopeForTrack()
    reaper.Main_OnCommand(40406, 0)
end

function showTrackVolumeEnvelope()
    reaper.Main_OnCommand(40070, 0)
end

function showTrimVolumeEnvelope(track)
    local volume_env = reaper.GetTrackEnvelopeByName(track, "Trim Volume")
    
    if not volume_env then
        reaper.SetOnlyTrackSelected(track)
        showVolumeEnvelopeForTrack()
        volume_env = reaper.GetTrackEnvelopeByName(track, "Trim Volume")
    end
    
    if volume_env then
        reaper.SetOnlyTrackSelected(track)
        showTrackVolumeEnvelope()
    end
    
    return volume_env
end

function addAutomationPoints(envelope, start_time, end_time, punch_db, fade_ms)
    if not envelope then
        return
    end
    
    local fade_seconds = fade_ms / 1000.0
    
    -- Calculate fade in/out times
    local fade_in_start = start_time - fade_seconds
    local fade_in_end = start_time
    local fade_out_start = end_time  
    local fade_out_end = end_time + fade_seconds
    
    -- Convert dB to envelope values
    local punch_value = dbToEnvelopeValue(punch_db)
    local normal_value = dbToEnvelopeValue(0) -- 0dB = no change
    
    -- Log what we're about to insert
    reaper.ShowConsoleMsg("Inserting points:\n")
    reaper.ShowConsoleMsg("  punch_db=" .. punch_db .. " -> punch_value=" .. punch_value .. "\n")
    reaper.ShowConsoleMsg("  0dB -> normal_value=" .. normal_value .. "\n")
    
    -- Add automation points with curves
    -- Point before fade in (normal volume)
    reaper.InsertEnvelopePoint(envelope, fade_in_start, normal_value, ENVELOPE_SHAPE_SLOW_START_END, 0, false, true)
    
    -- Fade in point (punched volume) 
    reaper.InsertEnvelopePoint(envelope, fade_in_end, punch_value, ENVELOPE_SHAPE_SLOW_START_END, 0, false, true)
    
    -- Fade out point (punched volume)
    reaper.InsertEnvelopePoint(envelope, fade_out_start, punch_value, ENVELOPE_SHAPE_SLOW_START_END, 0, false, true)
    
    -- Point after fade out (normal volume)
    reaper.InsertEnvelopePoint(envelope, fade_out_end, normal_value, ENVELOPE_SHAPE_SLOW_START_END, 0, false, true)
    
    reaper.Envelope_SortPoints(envelope)
end

function main()
    -- Get punch parameters from user
    local punch_db, fade_ms = showPunchEnvelopeDialog()
    if not punch_db then
        return
    end
    
    -- Get time selection
    local start_time, end_time = getTimeSelection()
    if not start_time then
        return
    end
    
    -- Get selected track
    local track = getSelectedTrack()
    if not track then
        return
    end
    
    reaper.Undo_BeginBlock()
    
    -- Show/get volume envelope
    local volume_envelope = showTrimVolumeEnvelope(track)
    if not volume_envelope then
        reaper.ShowMessageBox("Could not access volume envelope.", "Error", 0)
        reaper.Undo_EndBlock("Punch Envelope", -1)
        return
    end
    
    -- Add automation points
    addAutomationPoints(volume_envelope, start_time, end_time, punch_db, fade_ms)
    
    reaper.Undo_EndBlock("Punch Envelope", -1)
    reaper.UpdateArrange()
end

-- Run the script
main()