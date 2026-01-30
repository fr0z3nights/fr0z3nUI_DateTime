---@meta
-- LuaLS-only WoW API stubs.
-- Not referenced by the addon .toc; safe for the game client.

---@param prefix string
---@return boolean success
function RegisterAddonMessagePrefix(prefix) end

---@param prefix string
---@param text string
---@param distribution string
---@param target? string
function SendAddonMessage(prefix, text, distribution, target) end

---@class ChatThrottleLib
ChatThrottleLib = ChatThrottleLib

---@class C_ChatInfo
C_ChatInfo = C_ChatInfo
