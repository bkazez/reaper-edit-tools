# Reaper Lua Scripts Project

This project contains standalone REAPER Lua scripts for audio production and editing.

## Development Guidelines
- Each script must be self-contained and not depend on each other
- Use descriptive filenames and clear comment headers
- This is production code: write maintainable code with small, focused functions
- Code should be as succinct, simple, and DRY as possible
- Always check if required objects exist before operating on them
- Use `reaper.Undo_BeginBlock()` and `reaper.Undo_EndBlock()` for undoable operations
- Test scripts manually in REAPER before committing
- Don't directly call cryptic commands like `Main_OnCommand(40630, 0)`; instead, create wrapper functions for readability

## Testing Scripts
Scripts can be tested by launching REAPER with the script filename:
- `/Applications/REAPER.app/Contents/MacOS/REAPER -nonewinst script_name.lua`
