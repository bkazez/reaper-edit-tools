local M = {}

for key in pairs(reaper) do _G[key] = reaper[key] end

M.DEST_COLOR = ColorToNative(0, 0, 255) | 0x1000000
M.SOURCE_COLOR = ColorToNative(255, 128, 0) | 0x1000000

M.DEST_IN = "D<"
M.DEST_OUT = "D>"
M.SOURCE_IN = "S<"
M.SOURCE_OUT = "S>"

function M.get_selected_track_number()
    local track = GetSelectedTrack(0, 0)
    if not track then return 1 end
    return math.floor(GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
end

function M.make_marker_name(track_num, marker_type)
    return track_num .. ":" .. marker_type
end

function M.remove_marker_by_pattern(pattern)
    local retval, num_markers, num_regions = CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, marker_name, markrgnindexnumber, color = EnumProjectMarkers3(0, i)
        if marker_name:match(pattern) then
            DeleteProjectMarker(0, markrgnindexnumber, isrgn)
            break
        end
    end
end

function M.clear_existing_markers_of_type(marker_type)
    local retval, num_markers, num_regions = CountProjectMarkers(0)
    local markers_to_delete = {}
    
    ShowConsoleMsg("Looking for markers with type: " .. marker_type .. "\n")
    
    -- Collect all markers of this type first (to avoid index shifting during deletion)
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, marker_name, markrgnindexnumber, color = EnumProjectMarkers3(0, i)
        ShowConsoleMsg("Checking marker: '" .. marker_name .. "'\n")
        
        -- Simple pattern: any number, colon, then the marker type
        local pattern = "%d+:" .. marker_type:gsub("([<>])", "%%%1")
        ShowConsoleMsg("Using pattern: " .. pattern .. "\n")
        
        if marker_name:match(pattern) then
            ShowConsoleMsg("MATCH! Will delete marker: " .. marker_name .. "\n")
            table.insert(markers_to_delete, markrgnindexnumber)
        end
    end
    
    -- Delete them in reverse order to maintain indices
    for i = #markers_to_delete, 1, -1 do
        DeleteProjectMarker(0, markers_to_delete[i], false)
    end
    
    ShowConsoleMsg("Cleared " .. #markers_to_delete .. " existing " .. marker_type .. " markers\n")
end

function M.get_current_position()
    return (GetPlayState() == 0) and GetCursorPosition() or GetPlayPosition()
end

function M.find_marker_by_pattern(pattern)
    local retval, num_markers, num_regions = CountProjectMarkers(0)
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, marker_name, markrgnindexnumber, color = EnumProjectMarkers3(0, i)
        if marker_name:match(pattern) then
            return pos, markrgnindexnumber, marker_name
        end
    end
    return nil
end

function M.set_time_selection(start_pos, end_pos)
    GetSet_LoopTimeRange2(0, true, false, start_pos, end_pos, false)
end

function M.select_all_items_in_time_selection()
    Main_OnCommand(40718, 0)
end

function M.select_items_on_track_in_time_selection(track_number)
    local start_time, end_time = GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local track = GetTrack(0, track_number - 1)
    
    if not track then 
        ShowConsoleMsg("WARNING: Track " .. track_number .. " not found!\n")
        return 
    end
    
    local num_items = CountTrackMediaItems(track)
    for i = 0, num_items - 1 do
        local item = GetTrackMediaItem(track, i)
        local item_start = GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + GetMediaItemInfo_Value(item, "D_LENGTH")
        
        if item_start < end_time and item_end > start_time then
            SetMediaItemSelected(item, true)
        end
    end
end

function M.copy_selected_items()
    Main_OnCommand(41383, 0)
end

function M.delete_selected_items()
    Main_OnCommand(40201, 0)
end

function M.with_trim_content_behind_items(enabled, func)
    local original_state = GetToggleCommandState(41117)
    
    -- Set the desired state
    if (enabled and original_state == 0) or (not enabled and original_state == 1) then
        Main_OnCommand(41117, 0)
    end
    
    -- Execute the function
    func()
    
    -- Restore original state
    local current_state = GetToggleCommandState(41117)
    if current_state ~= original_state then
        Main_OnCommand(41117, 0)
    end
end

function M.select_track(track_number)
    M.clear_track_selection()
    local track = GetTrack(0, track_number - 1)
    if track then
        SetTrackSelected(track, true)
        return true
    end
    ShowConsoleMsg("ERROR: Could not get track " .. track_number .. "\n")
    return false
end

function M.paste_items_to_selected_track()
    -- Use "Paste items/tracks" which should only paste to selected tracks
    Main_OnCommand(40058, 0)
end

function M.paste_items()
    Main_OnCommand(42398, 0)
end

function M.clear_time_selection()
    Main_OnCommand(40020, 0)
end

function M.get_time_selection()
    return GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
end

function M.restore_time_selection(start_time, end_time)
    if start_time == end_time then
        M.clear_time_selection()
    else
        GetSet_LoopTimeRange2(0, true, false, start_time, end_time, false)
    end
end

function M.clear_item_selection()
    Main_OnCommand(40289, 0)
end

function M.go_to_time_selection_start()
    Main_OnCommand(40630, 0)
end

function M.clear_track_selection()
    Main_OnCommand(40297, 0)
end

function M.set_edit_cursor_to_track(track_number)
    -- Set the edit cursor to be on the specified track
    local track = GetTrack(0, track_number - 1)
    if track then
        SetOnlyTrackSelected(track)
        Main_OnCommand(40913, 0)  -- Vertical scroll selected tracks into view
        return true
    end
    return false
end

function M.disable_track_grouping()
    local group_state = GetToggleCommandState(1156)
    Main_OnCommand(1156, 0)
    return group_state
end

function M.restore_track_grouping(previous_state)
    local current_state = GetToggleCommandState(1156)
    if current_state ~= previous_state then
        Main_OnCommand(1156, 0)
    end
end

return M