-- Part of reaper-edit-tools
-- Export Selected Items to OTIO - Convert selected media items to OpenTimelineIO format


function msg(text)
    reaper.ShowConsoleMsg(tostring(text) .. "\n")
end

function seconds_to_rational_time(seconds)
    return {
        ["OTIO_SCHEMA"] = "RationalTime.1",
        rate = 1.0,
        value = seconds
    }
end

function format_time_range(start_seconds, duration_seconds)
    return {
        ["OTIO_SCHEMA"] = "TimeRange.1",
        start_time = seconds_to_rational_time(start_seconds),
        duration = seconds_to_rational_time(duration_seconds)
    }
end

function get_project_info()
    local project_name = reaper.GetProjectName(0, "")
    if project_name == "" then
        project_name = "Untitled Project"
    end
    local sample_rate = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    return project_name, sample_rate
end

function get_project_framerate()
    local fps = reaper.TimeMap_curFrameRate(0)
    if fps <= 0 then
        error("Error: Project framerate not set. Please set a project framerate in REAPER project settings.")
    end
    return fps
end

function strip_file_extension(filename)
    return filename:gsub("%.%w+$", "")
end

function get_selected_media_items_with_bounds()
    local items = {}
    local tracks_used = {}
    local num_items = reaper.CountSelectedMediaItems(0)
    
    if num_items == 0 then
        msg("Error: No media items selected")
        return nil
    end
    
    local selection_start = math.huge
    local selection_end = -math.huge
    
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local track_number = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
        
        -- Track which tracks are used
        tracks_used[track_number] = true
        
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_start + item_length
        
        -- Update selection bounds
        selection_start = math.min(selection_start, item_start)
        selection_end = math.max(selection_end, item_end)
        
        local take = reaper.GetActiveTake(item)
        if take then
            local take_name = reaper.GetTakeName(take)
            if take_name == "" then
                take_name = "Unnamed Take " .. i
            else
                take_name = strip_file_extension(take_name)
            end
            
            local take_start_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            
            local source_in = take_start_offset
            local source_duration = item_length / playrate
            
            -- Timeline positions relative to selection start will be calculated later
            local timeline_in = item_start - selection_start
            local timeline_duration = item_length
            
            table.insert(items, {
                name = take_name,
                source_in = source_in,
                source_duration = source_duration,
                timeline_in = timeline_in,
                timeline_duration = timeline_duration
            })
        end
    end
    
    -- Check if items are on multiple tracks
    local track_count = 0
    for _ in pairs(tracks_used) do
        track_count = track_count + 1
    end
    
    if track_count > 1 then
        msg("Error: Selected media items are on multiple tracks (" .. track_count .. " tracks). Please select items from a single track only.")
        return nil
    end
    
    return items, selection_start, selection_end
end

function find_enclosing_region(selection_start, selection_end)
    local num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total_markers = num_markers + num_regions
    
    for i = 0, total_markers - 1 do
        local retval, isrgn, pos, rgnend, region_name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
        if retval and isrgn then
            -- Check if region completely encloses the selection
            if pos <= selection_start and rgnend >= selection_end then
                return region_name
            end
        end
    end
    return nil
end

function get_output_path(filename_base)
    local retval, render_path = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
    if render_path == "" then
        -- Fallback to project directory
        render_path = reaper.GetProjectPath("")
        if render_path:match("/Media$") then
            render_path = render_path:gsub("/Media$", "")
        end
    else
        -- If render_path is relative, make it absolute
        if not render_path:match("^/") then
            local project_path = reaper.GetProjectPath("")
            if project_path:match("/Media$") then
                project_path = project_path:gsub("/Media$", "")
            end
            render_path = project_path .. "/" .. render_path
        end
        -- Ensure the directory exists
        reaper.RecursiveCreateDirectory(render_path, 0)
    end
    return render_path .. "/" .. filename_base
end


function empty_array()
    -- Return a special marker for empty arrays
    return "JSON_ARRAY"
end

function create_media_reference(name, source_in, source_duration)
    return {
        ["OTIO_SCHEMA"] = "MediaReference.1",
        metadata = {},
        name = name,
        available_range = format_time_range(source_in, source_duration),
        available_image_bounds = json_null()
    }
end

function create_clip(name, source_in, source_duration)
    return {
        ["OTIO_SCHEMA"] = "Clip.2",
        metadata = {},
        name = name,
        source_range = format_time_range(source_in, source_duration),
        effects = empty_array(),
        markers = empty_array(),
        enabled = true,
        media_references = {
            DEFAULT_MEDIA = create_media_reference(name, source_in, source_duration)
        },
        active_media_reference_key = "DEFAULT_MEDIA"
    }
end

function create_track(track_name, clips)
    return {
        ["OTIO_SCHEMA"] = "Track.1",
        metadata = {},
        name = track_name,
        source_range = json_null(),
        effects = empty_array(),
        markers = empty_array(),
        enabled = true,
        children = clips,
        kind = "Video"
    }
end

function create_timeline(project_name, sample_rate, tracks)
    return {
        ["OTIO_SCHEMA"] = "Timeline.1",
        metadata = {},
        name = '"exported from reaper"',
        global_start_time = {
            ["OTIO_SCHEMA"] = "RationalTime.1",
            rate = 96000.0,
            value = 0.0
        },
        tracks = {
            ["OTIO_SCHEMA"] = "Stack.1",
            metadata = {},
            name = "tracks",
            source_range = json_null(),
            effects = empty_array(),
            markers = empty_array(),
            enabled = true,
            children = tracks
        }
    }
end

function json_null()
    -- Return a special marker for null values
    return "JSON_NULL"
end

function is_array(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

function get_ordered_keys(obj, obj_type)
    -- Define field order to match Python OTIO output
    local orders = {
        Timeline = {"OTIO_SCHEMA", "metadata", "name", "global_start_time", "tracks"},
        Stack = {"OTIO_SCHEMA", "metadata", "name", "source_range", "effects", "markers", "enabled", "children"},
        Track = {"OTIO_SCHEMA", "metadata", "name", "source_range", "effects", "markers", "enabled", "children", "kind"},
        Clip = {"OTIO_SCHEMA", "metadata", "name", "source_range", "effects", "markers", "enabled", "media_references", "active_media_reference_key"},
        MediaReference = {"OTIO_SCHEMA", "metadata", "name", "available_range", "available_image_bounds"},
        TimeRange = {"OTIO_SCHEMA", "duration", "start_time"},
        RationalTime = {"OTIO_SCHEMA", "rate", "value"}
    }
    
    local schema = obj["OTIO_SCHEMA"]
    local order = nil
    if schema then
        local schema_type = schema:match("([^%.]+)")
        order = orders[schema_type]
    end
    
    if order then
        local ordered = {}
        -- Add keys in defined order
        for _, key in ipairs(order) do
            if obj[key] ~= nil then
                table.insert(ordered, key)
            end
        end
        -- Add any remaining keys
        for key, _ in pairs(obj) do
            local found = false
            for _, ordered_key in ipairs(ordered) do
                if key == ordered_key then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(ordered, key)
            end
        end
        return ordered
    else
        -- Default: return keys in pairs() order
        local keys = {}
        for k, _ in pairs(obj) do
            table.insert(keys, k)
        end
        return keys
    end
end

function json_encode(obj)
    if obj == "JSON_NULL" then
        return "null"
    elseif obj == "JSON_ARRAY" then
        return "[]"
    elseif type(obj) == "table" then
        if next(obj) == nil then
            return "{}"
        end
        
        if is_array(obj) then
            -- Handle as array
            local parts = {}
            for i = 1, #obj do
                table.insert(parts, json_encode(obj[i]))
            end
            return "[" .. table.concat(parts, ", ") .. "]"
        else
            -- Handle as object with ordered keys
            local parts = {}
            local ordered_keys = get_ordered_keys(obj)
            for _, k in ipairs(ordered_keys) do
                local v = obj[k]
                local key = '"' .. tostring(k) .. '"'
                local value = json_encode(v)
                table.insert(parts, key .. ": " .. value)
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    elseif type(obj) == "string" then
        return '"' .. obj:gsub('"', '\\"') .. '"'
    elseif type(obj) == "boolean" then
        return tostring(obj)
    elseif type(obj) == "number" then
        return tostring(obj)
    else
        return "null"
    end
end



function main()
    local project_name, sample_rate = get_project_info()
    local fps = get_project_framerate()
    msg("Project: " .. project_name)
    msg("Sample Rate: " .. sample_rate)
    msg("Project FPS: " .. fps)
    
    -- Get selected media items
    local media_items, selection_start, selection_end = get_selected_media_items_with_bounds()
    if not media_items then
        return
    end
    
    local selection_duration = selection_end - selection_start
    msg("Processing " .. #media_items .. " selected media items")
    msg("Selection bounds: " .. selection_start .. " to " .. selection_end .. " (" .. selection_duration .. "s)")
    
    -- Check if selection is enclosed by a region
    local enclosing_region = find_enclosing_region(selection_start, selection_end)
    local filename_base = enclosing_region or "selected_items"
    if enclosing_region then
        msg("Selection is enclosed by region: " .. enclosing_region)
    end
    
    -- Create OTIO clips
    local clips = {}
    for _, item in ipairs(media_items) do
        msg("  " .. item.name .. ": source[" .. item.source_in .. ", " .. (item.source_in + item.source_duration) .. "] timeline[" .. item.timeline_in .. ", " .. (item.timeline_in + item.timeline_duration) .. "]")
        local clip = create_clip(item.name, item.source_in, item.source_duration)
        table.insert(clips, clip)
    end
    
    -- Create track and timeline
    local video_track = create_track("Track 1", clips)
    local timeline = create_timeline(project_name, sample_rate, {video_track})
    
    -- Convert to JSON
    local otio_json = json_encode(timeline)
    
    -- Write to file
    local output_file = get_output_path(filename_base .. ".otio")
    
    local file = io.open(output_file, "w")
    if file then
        file:write(otio_json)
        file:close()
        msg("OTIO file written to: " .. output_file)
    else
        msg("Error: Could not write to file " .. output_file)
        return
    end
    
end

-- Run the script
reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Export Region to OTIO", -1)
