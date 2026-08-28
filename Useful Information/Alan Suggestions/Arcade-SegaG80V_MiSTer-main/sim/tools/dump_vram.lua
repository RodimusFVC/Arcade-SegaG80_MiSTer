-- Dump the Sega G-80 vector RAM ($E000-$EFFF) periodically while MAME runs.
--
-- The snapshots serve two purposes:
--   1. Phase 0 colour census — walk them with the golden model and count which
--      of the 64 attribute colours the games actually emit, which decides
--      whether videodr0me_fb's colour path has to be widened at all.
--   2. Real regression stimulus for the RTL bench, replacing synthetic display
--      lists with actual game data.
--
-- Usage:
--   mame <game> -rompath <dir> -video none -sound none -nothrottle \
--        -seconds_to_run N -autoboot_script dump_vram.lua
--
-- Output directory and cadence come from the environment:
--   SEGAVRAM_OUT     directory to write into (default ".")
--   SEGAVRAM_EVERY   dump every N frames (default 20)
--   SEGAVRAM_COIN    if set, insert a coin and press start early on

local outdir   = os.getenv("SEGAVRAM_OUT")   or "."
local every    = tonumber(os.getenv("SEGAVRAM_EVERY")) or 20
local do_coin  = os.getenv("SEGAVRAM_COIN")  ~= nil

local mac    = manager.machine
local frame  = 0
local dumped = 0

-- Prefer the named memory share; fall back to the CPU program space.
local share = mac.memory.shares[":vectorram"]
local space = nil
if not share then
	space = mac.devices[":maincpu"].spaces["program"]
end

local function read_vram()
	local t = {}
	if share then
		for i = 0, 0xFFF do t[#t + 1] = string.char(share:read_u8(i)) end
	else
		for a = 0xE000, 0xEFFF do t[#t + 1] = string.char(space:read_u8(a)) end
	end
	return table.concat(t)
end

-- Coin/start pressing, so the census sees gameplay and not only attract mode.
local coin_field, start_field
if do_coin then
	for _, port in pairs(mac.ioport.ports) do
		for _, field in pairs(port.fields) do
			if not coin_field  and field.name:find("Coin 1")   then coin_field  = field end
			if not start_field and field.name:find("1 Player") then start_field = field end
		end
	end
end

local function on_frame()
	frame = frame + 1

	if do_coin then
		-- field.live.value is read-only in this API; set_value() is the setter
		if coin_field then
			coin_field:set_value((frame > 120 and frame < 130) and 1 or 0)
		end
		if start_field then
			start_field:set_value((frame > 180 and frame < 190) and 1 or 0)
		end
	end

	if frame % every == 0 then
		local f = io.open(string.format("%s/vram_%05d.bin", outdir, frame), "wb")
		if f then
			f:write(read_vram())
			f:close()
			dumped = dumped + 1
		end
	end
end

-- MAME renamed this hook; support both spellings.
--
-- add_machine_frame_notifier returns a subscription object that unsubscribes
-- when collected, so it MUST be kept alive in a global. Dropping it silently
-- stops the notifier after a handful of frames.
if emu.add_machine_frame_notifier then
	_G.segavram_sub = emu.add_machine_frame_notifier(on_frame)
elseif emu.register_frame_done then
	emu.register_frame_done(on_frame)
else
	print("SEGAVRAM: no frame notifier available in this MAME Lua API")
end

print(string.format("SEGAVRAM: out=%s every=%d coin=%s share=%s",
	outdir, every, tostring(do_coin), tostring(share ~= nil)))
