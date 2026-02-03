# fr0z3nUI DateTime

Movable date/time display with an options UI and a few convenience commands.

## Install
1. Copy the folder `fr0z3nUI_DateTime` into:
	- `World of Warcraft/_retail_/Interface/AddOns/`
2. Launch WoW and enable the addon.

## Slash Commands
- `/fdt` — open options
- `/fdt help` — same as `/fdt`

### State / formatting
- `/fdt toggle` — enable/disable
- `/fdt lock` — lock position
- `/fdt unlock` — unlock (drag to move)
- `/fdt 24` — 24-hour time
- `/fdt 12` — 12-hour time
- `/fdt seconds` — toggle seconds
- `/fdt scale <number>` — set scale (clamped 0.5–2.0)
- `/fdt reset` — reset settings to defaults

### Debug
- `/fdt debugfont` — font debug + reapply
- `/fdt debuglsm` — LibSharedMedia debug
- `/fdt debuglibs` — prints bundled lib load status

### Timewalking helpers
- `/fdt twlist` — print Timewalking dungeon list (when module is available)
- `/fdt twid` (or `shadowlands` / `sl`) — prints Shadowlands TW hint

## SavedVariables
- Account: `fr0z3nUI_DateTimeDB`
- Character: `fr0z3nUI_DateTimeCharDB`

## Dependencies
- Optional: `Ace3`, `LibSharedMedia-3.0` (bundled fallbacks included).
