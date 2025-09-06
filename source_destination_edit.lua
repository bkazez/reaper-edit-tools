-- reaper-edit-tools
-- Source Destination Edit: Performs edit operation using source and destination markers
-- Author: Ben Kazez
-- GitHub: https://github.com/bkazez/reaper-edit-tools

local script_path = debug.getinfo(1, "S").source:match("@(.*)[\\/][^\\/]*$")
if script_path then
    package.path = package.path .. ";" .. script_path .. "/?.lua"
end

local common = require("source_destination_common")

function find_all_markers()
    local source_markers = {}
    local dest_markers = {}
    local retval, num_markers, num_regions = CountProjectMarkers(0)
    
    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, marker_name, markrgnindexnumber, color = EnumProjectMarkers3(0, i)
        local track_num, marker_type = marker_name:match("(%d+):([SD][<>])")
        
        if track_num and marker_type then
            track_num = tonumber(track_num)
            ShowConsoleMsg("Marker " .. marker_name .. " has color: " .. color .. " (source=" .. common.SOURCE_COLOR .. ", dest=" .. common.DEST_COLOR .. ")\n")
            -- More robust color matching - check if colors are close enough
            local color_diff_source = math.abs(color - common.SOURCE_COLOR)
            local color_diff_dest = math.abs(color - common.DEST_COLOR)
            local is_source = (color_diff_source <= color_diff_dest and color_diff_source < 100000)
            local is_dest = (color_diff_dest < color_diff_source and color_diff_dest < 100000)
            
            if is_source then
                if not source_markers[track_num] then
                    source_markers[track_num] = {}
                end
                if marker_type == common.SOURCE_IN then
                    source_markers[track_num].in_marker = pos
                elseif marker_type == common.SOURCE_OUT then
                    source_markers[track_num].out_marker = pos
                end
            elseif is_dest then
                if not dest_markers[track_num] then
                    dest_markers[track_num] = {}
                end
                if marker_type == common.DEST_IN then
                    dest_markers[track_num].in_marker = pos
                elseif marker_type == common.DEST_OUT then
                    dest_markers[track_num].out_marker = pos
                end
            end
        end
    end
    
    return source_markers, dest_markers
end

function count_total_markers(markers)
    local count = 0
    for track_num, track_markers in pairs(markers) do
        for marker_type, pos in pairs(track_markers) do
            count = count + 1
        end
    end
    return count
end

function find_source_and_destination_tracks(markers)
    local tracks_with_markers = {}
    
    for track_num, track_markers in pairs(markers) do
        if track_markers.in_marker or track_markers.out_marker then
            table.insert(tracks_with_markers, track_num)
        end
    end
    
    if #tracks_with_markers < 2 then
        return nil, nil
    end
    
    return tracks_with_markers[1], tracks_with_markers[2]
end

function calculate_missing_markers(source_markers, dest_markers)
    local source_track = next(source_markers)
    local dest_track = next(dest_markers)
    local source = source_markers[source_track]
    local dest = dest_markers[dest_track]
    
    -- Calculate missing marker positions in memory only (don't create actual markers)
    if source.in_marker and source.out_marker then
        local duration = source.out_marker - source.in_marker
        if dest.in_marker and not dest.out_marker then
            dest.out_marker = dest.in_marker + duration
            ShowConsoleMsg("Calculated missing dest out marker at: " .. dest.out_marker .. "\n")
        elseif dest.out_marker and not dest.in_marker then
            dest.in_marker = dest.out_marker - duration
            ShowConsoleMsg("Calculated missing dest in marker at: " .. dest.in_marker .. "\n")
        end
    elseif dest.in_marker and dest.out_marker then
        local duration = dest.out_marker - dest.in_marker
        if source.in_marker and not source.out_marker then
            source.out_marker = source.in_marker + duration
            ShowConsoleMsg("Calculated missing source out marker at: " .. source.out_marker .. "\n")
        elseif source.out_marker and not source.in_marker then
            source.in_marker = source.out_marker - duration
            ShowConsoleMsg("Calculated missing source in marker at: " .. source.in_marker .. "\n")
        end
    end
    
    -- Return true if we now have all 4 markers
    return source.in_marker and source.out_marker and dest.in_marker and dest.out_marker
end

function perform_edit(source, dest, source_track, dest_track)
    
    -- Use the existing calculate_missing_markers function for 3-point editing
    local source_markers_temp = {}
    local dest_markers_temp = {}
    source_markers_temp[source_track] = source
    dest_markers_temp[dest_track] = dest
    
    if not calculate_missing_markers(source_markers_temp, dest_markers_temp) then
        ShowConsoleMsg("Unable to calculate missing markers for 3-point editing\n")
        return false
    end
    
    if not (source.in_marker and source.out_marker and dest.in_marker and dest.out_marker) then
        ShowConsoleMsg("Missing required markers after calculation\n")
        return false
    end
    
    -- Copy items from source track
    common.clear_track_selection()
    common.set_time_selection(source.in_marker, source.out_marker)
    common.clear_item_selection()
    common.select_items_on_track_in_time_selection(source_track)
    common.copy_selected_items()
    
    -- Select destination track and paste
    if not common.select_track(dest_track) then
        ShowConsoleMsg("ERROR: Could not select destination track " .. dest_track .. "\n")
        return false
    end
    
    common.set_time_selection(dest.in_marker, dest.out_marker)
    common.go_to_time_selection_start()
    common.set_edit_cursor_to_track(dest_track)
    
    common.with_trim_content_behind_items(true, function()
        common.paste_items()
    end)
    
    common.clear_item_selection()
    
    return true
end

function main()
    ShowConsoleMsg("=== Starting Source-Destination Edit ===\n")
    Undo_BeginBlock()
    
    local group_state = common.disable_track_grouping()
    local original_time_start, original_time_end = common.get_time_selection()
    
    local source_markers, dest_markers = find_all_markers()
    
    if not next(source_markers) or not next(dest_markers) then
        ShowMessageBox("Need both source (orange) and destination (blue) markers", "Error", 0)
        common.restore_time_selection(original_time_start, original_time_end)
        common.restore_track_grouping(group_state)
        Undo_EndBlock("Source-Destination Edit", 0)
        return
    end
    
    -- Get the first (lowest) track number from each marker set
    local source_track = nil
    local dest_track = nil
    
    for track_num in pairs(source_markers) do
        if not source_track or track_num < source_track then
            source_track = track_num
        end
    end
    
    for track_num in pairs(dest_markers) do
        if not dest_track or track_num < dest_track then
            dest_track = track_num
        end
    end
    
    if not source_track or not dest_track then
        ShowMessageBox("Could not find valid source and destination tracks from markers", "Error", 0)
        common.restore_time_selection(original_time_start, original_time_end)
        common.restore_track_grouping(group_state)
        Undo_EndBlock("Source-Destination Edit", 0)
        return
    end
    
    ShowConsoleMsg("Source track: " .. source_track .. ", Dest track: " .. dest_track .. "\n")
    
    if perform_edit(source_markers[source_track], dest_markers[dest_track], source_track, dest_track) then
        UpdateArrange()
    else
        ShowMessageBox("Edit failed", "Error", 0)
    end
    
    common.restore_time_selection(original_time_start, original_time_end)
    common.restore_track_grouping(group_state)
    Undo_EndBlock("Source-Destination Edit", 0)
end

main()