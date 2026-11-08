-- Sell Dirt loader for Delta Executor (Android)
-- 1) Host dist/SellDirt.lua at a RAW HTTPS URL (GitHub raw / Pastebin raw / etc.)
-- 2) Replace the URL below.
-- 3) Execute this loader in Delta while in Sell Dirt.

getgenv().SD_LOADSTRING_URL = "https://YOUR_HOST_HERE/SellDirt.lua"

local ok, err = pcall(function()
	return loadstring(game:HttpGet(getgenv().SD_LOADSTRING_URL))()
end)

if not ok then
	warn("[Sell Dirt Loader] failed: " .. tostring(err))
end
