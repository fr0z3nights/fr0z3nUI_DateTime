# fr0z3nUI_DateTime — Changelog

Format: `YYYY.MM.DD.NN` (TOC `## Version`) — short summary. Newest at the top.

Discipline: bump TOC `## Version` on every behavior/UI change (sanity check stays meaningful).

# 2026.10.20.08
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README Changelog.md`.
- Simplify the Hallow's End button tooltip to the single line "Hallow's End Queue".

# 2026.10.20.07
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README.md`, `README Changelog.md`.
- Use only the Black Cat icon (236547) for Hallow's End; remove icon randomization on world entry. Preserve circular mask, zoom, size, and queue behavior.

# 2026.10.20.06
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README.md`, `README Changelog.md`.
- Randomize the Hallow's End icon on every PLAYER_ENTERING_WORLD, including teleports, instead of only at button creation. Routine visibility updates do not reroll it.

# 2026.10.20.05
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README.md`, `README Changelog.md`.
- Randomly choose the Hallow's End button icon once on login/reload from Spider (236551), Black Cat (236547), Vampire Bat (236546), and Witch (236552). Preserve the chosen icon across visibility updates, with existing circular mask, zoom, and size unchanged.

# 2026.10.20.04
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README Changelog.md`.
- Increase the Hallow's End button from 26 to 28.6 UI units (10%) and zoom its artwork another 5% (1.1025x total), retaining the circular mask.

# 2026.10.20.03
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README Changelog.md`.
- Zoom the Hallow's End icon artwork by 5% inside its existing circular mask; keep button size unchanged.

# 2026.10.20.02
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README.md`, `README Changelog.md`.
- Mask the Hallow's End quick-queue icon to a circle, removing its visible square corners without changing its size or click behavior.

# 2026.10.20.01
- Files: `fr0z3nUI_DateTime.lua`, `fr0z3nUI_DateTime.toc`, `README.md`, `README Changelog.md`.
- Add Hallow's End Headless Horseman quick-queue button (LFG 285), using icon 236551 and Loot-Filled Pumpkin reward 209024. Follow holiday calendar, daily reward, placement, combat, and instance visibility rules, with retries for unavailable data.
- Scope the Heart-Shaped Box loot fallback to the Valentine's dungeon so it does not suppress other holiday buttons.

# 2026.03.01.01
- Added `/fdt version` (and `/fdt ver`) to print sanity stamp, addon version, and Interface/build info.
- README note: clarified embedded libs under `Libs/` vs `OptionalDeps` behavior.
