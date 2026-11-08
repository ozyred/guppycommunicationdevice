local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local svc = game:GetService(("ecivreStahCtxeT"):reverse())
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local opts = {
	ver = 1,
	range = 75,
	short = 8,
	near = 20,
	burst = 8,
	window = 2,
	maxlen = 200,
	cmdlen = 1000,
	strict = true,
	rank = 3,
	guiname = "link",
	linkname = "link",
	tint = "rgb(125, 200, 255)",
	font = "Cartoon",
	debug = false,
}

local cmds = {
	m = "Message",
	cm = "CharacterMessage",
	sm = "",
	notif = true,
	snotif = true,
	schat = true,
}

local mod = {}
mod.Config = opts

local base = (script and script:FindFirstChild("guppyco")) or ServerStorage:FindFirstChild("guppyco")
local on = false
local link = nil
local cmdlink = nil
local conns = {}
local watch = {}
local rates = {}
local seen = {}

local function log(...)
	if opts.debug then
		print("[link]", ...)
	end
end

local function dig(root, path)
	for part in path:gmatch("[^%.]+") do
		root = root and root:FindFirstChild(part)
	end
	return root
end

local function load(root, path)
	local obj = dig(root, path)
	if not obj or not obj:IsA("ModuleScript") then
		return nil
	end
	local ok, res = pcall(require, obj)
	return ok and res or nil
end

local txt = load(ReplicatedStorage, "Modules.ChatText")
local fmt = load(ReplicatedStorage, "Modules.MDify.MDify")
local names = load(ServerScriptService, "ServerModules.Introductions")
local dict = load(ReplicatedStorage, "LanguageDictionary")
local mix = load(ServerScriptService, "MHandler.GarbleSystem")

local function remotes()
	return ReplicatedStorage:FindFirstChild("Remotes")
end

local function fx()
	local folder = remotes()
	return folder and folder:FindFirstChild("ClientEffects")
end

local function trim(str)
	return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cut(str, max)
	local at = utf8.offset(str, max + 1)
	if at then
		return str:sub(1, at - 1)
	end
	return str
end

local function stamp()
	local short = ""
	for _, part in tostring(os.date("%Z")):split(" ") do
		short ..= part:sub(1, 1)
	end
	return os.date("%I") .. ":" .. os.date("%M") .. " " .. short
end

local function allow(plr)
	local now = os.clock()
	local rate = rates[plr]
	if not rate or now - rate.Start > opts.window then
		rate = { Start = now, Count = 0 }
		rates[plr] = rate
	end
	rate.Count += 1
	return rate.Count <= opts.burst
end

local function rank(plr)
	if RunService:IsStudio() then
		return 5
	end
	return tonumber(plr:GetAttribute("StaffRank")) or 0
end

local function notice(plr, str)
	local ce = fx()
	if ce then
		ce:FireClient(plr, "PMHolder", { Caller = plr, Message = str })
	end
end

local function reach(loudguy, nosyguy)
	if not opts.strict or loudguy == nosyguy then
		return true
	end
	local key = loudguy.UserId .. ":" .. nosyguy.UserId
	local hit = seen[key]
	local now = os.clock()
	if hit and now - hit.At < 60 then
		return hit.Ok
	end
	local ok, res = pcall(svc.CanUsersChatAsync, svc, loudguy.UserId, nosyguy.UserId)
	local allowed = not ok or res == true
	seen[key] = { At = now, Ok = allowed }
	return allowed
end

local function near(origin, range)
	local list = {}
	for _, other in Players:GetPlayers() do
		local char = other.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - origin).Magnitude <= range then
			table.insert(list, other)
		end
	end
	return list
end

local function owner(plr)
	local alive = workspace:FindFirstChild("Alive")
	return (alive and alive:FindFirstChild(plr.Name .. "_Corpse")) or plr.Character
end

local function flagged(plr)
	if mix and type(mix.IsGarbled) == "function" then
		local ok, res = pcall(mix.IsGarbled, plr.UserId)
		if ok then
			return res == true
		end
	end
	return plr:GetAttribute("ChatGarbled") == true
end

local function escape(str)
	if txt and txt.Escape then
		return txt.Escape(str)
	end
	return (str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function markup(str)
	if fmt and fmt.MarkdownToRichText then
		local ok, res = pcall(fmt.MarkdownToRichText, str)
		if ok and type(res) == "string" then
			return res
		end
	end
	return str
end

local function prep(str, ctx)
	if str:find("{.-}") then
		str = str:gsub("[{}]", "")
	end
	str = markup(escape(str))
	if txt then
		if ctx.flagged and txt.Garble then
			local ok, res = pcall(txt.Garble, str)
			if ok and type(res) == "string" then
				str = res
			end
		end
		if ctx.down and txt.Downed then
			local ok, res = pcall(txt.Downed, str)
			if ok and type(res) == "string" then
				str = res
			end
		end
		if (ctx.merry or 0) > 0 and txt.Merry then
			local ok, res = pcall(txt.Merry, str, ctx.merry)
			if ok and type(res) == "string" then
				str = res
			end
		end
	end
	return str
end

local function known(nosyguy)
	local char = nosyguy.Character
	local data = char and char:FindFirstChild("PlayerData")
	return string.split(data and data:GetAttribute("KnownLanguages") or "", ",")
end

local function tint(ctx, msg)
	if not ctx.actor:GetAttribute("FairyFlight") then
		return msg
	end
	return '<font color="' .. opts.tint .. '" face="' .. opts.font .. '">' .. msg .. "</font>"
end

local function encode(str, mode, actor, nosyguy)
	local out = {}
	local pos = 1
	while pos <= #str do
		local first, last = str:find("<[^>]*>", pos)
		local efirst, elast = str:find("&#?%w+;", pos)
		if efirst and (not first or efirst < first) then
			first, last = efirst, elast
		end
		if not first then
			table.insert(out, dict.Cipher(str:sub(pos), mode, actor, nosyguy, false))
			break
		end
		if first > pos then
			table.insert(out, dict.Cipher(str:sub(pos, first - 1), mode, actor, nosyguy, false))
		end
		table.insert(out, str:sub(first, last))
		pos = last + 1
	end
	return table.concat(out)
end

local specials = {
	Sinner = function(str, isknown)
		return isknown and ("[SINNER] < " .. str .. " >") or "< . . . >"
	end,
	Scroomspeech = function(str, isknown)
		return isknown and ("[S] " .. str) or ". . ."
	end,
	SignLanguage = function(str, isknown)
		return isknown and ("[SGN] < " .. str .. " >") or nil
	end,
	LM_450 = function(str, isknown)
		if isknown then
			return "[LM] " .. str
		end
		local words = {}
		for _ in string.gmatch(str, "%S+") do
			table.insert(words, math.random(1, 2) == 1 and "Beep" or "push")
		end
		return table.concat(words, " ")
	end,
}

local function shape(nosyguy, ctx, msg)
	if ctx.kind == "Thought" then
		msg = "[ " .. msg .. " ]"
	elseif ctx.kind == "Whisper" then
		msg = '<font size="13"> [w] ' .. msg .. "</font>  "
	end
	local mode = ctx.mode
	if mode == "Default" or not dict then
		return tint(ctx, msg)
	end
	local isknown = table.find(known(nosyguy), mode) ~= nil
	local specok, spec = pcall(dict.IsSpecial, mode)
	if specok and spec then
		local rule = specials[mode]
		if rule then
			return rule(msg, isknown)
		end
		return isknown and msg or nil
	end
	if isknown then
		local colorok, color = pcall(dict.GetColor, mode)
		if colorok and color then
			msg = '<font color="' .. color .. '">' .. msg .. "</font>"
		end
		return tint(ctx, msg)
	end
	local encodeok, encoded = pcall(encode, msg, mode, ctx.actor, nosyguy)
	return tint(ctx, encodeok and encoded or msg)
end

local function play(src, actor, setup)
	if not src or not src:IsA("Sound") then
		return
	end
	local copy = src:Clone()
	copy.Parent = actor:FindFirstChild("Head") or actor
	if setup then
		setup(copy)
	end
	copy:Play()
	Debris:AddItem(copy, 5)
end

local sfx = {
	Sinner = function(str, actor)
		local folder = dig(ReplicatedStorage, "Assets.Clockwork")
		if not folder then
			return
		end
		local name = "D_Normal"
		if str:find("!!", 1, true) then
			name = "D_Angry"
		elseif str:find("??", 1, true) then
			name = "D_Click"
		elseif str:find("!?", 1, true) or str:find("?!", 1, true) then
			name = "D_Surprise"
		end
		play(folder:FindFirstChild(name), actor)
	end,
	Scroomspeech = function(_, actor)
		play(dig(ReplicatedStorage, "Sounds.Squeak"), actor, function(sound)
			local data = actor:FindFirstChild("PlayerData")
			data = data and data.Value
			local race = data and data:FindFirstChild("Race")
			if not race then
				return
			end
			if race.Value ~= "Scroom" then
				sound.PlaybackSpeed = 0.8
			end
			if race.Value == "Metascroom" then
				local reverb = sound:FindFirstChild("ReverbSoundEffect")
				if reverb then
					reverb.Enabled = true
				end
			end
		end)
	end,
	SignLanguage = function(str, actor)
		local folder = dig(ReplicatedStorage, "Animations.Sign")
		local hum = actor:FindFirstChildOfClass("Humanoid")
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if not folder or not anim then
			return
		end
		local low = string.lower(str)
		local short = #low < 15
		local yesno = #low <= 3 or low:find("yes") ~= nil or low:find("no") ~= nil
		local name
		if short and not yesno then
			if low:find("mute") and #low <= 9 then
				name = (low:find("im") or low:find("i'm")) and "Mute" or ("Small" .. math.random(1, 3))
			elseif low:find("deaf") and #low <= 9 then
				name = (low:find("im") or low:find("i'm")) and "Deaf" or ("Small" .. math.random(1, 3))
			else
				name = "Small" .. math.random(1, 3)
			end
		elseif short and yesno then
			if low:find("yes") and not low:find("no") then
				name = "Yes"
			elseif low:find("no") and not low:find("yes") then
				name = "No"
			else
				name = "Small" .. math.random(1, 3)
			end
		else
			name = "LongSet" .. math.random(1, 3)
		end
		local animation = folder:FindFirstChild(name)
		if animation then
			anim:LoadAnimation(animation):Play()
		end
	end,
	LM_450 = function(str, actor)
		local folder = dig(ReplicatedStorage, "Sounds.Robotica")
		if not folder then
			return
		end
		local beeps = { folder:FindFirstChild("Beep1"), folder:FindFirstChild("Beep2"), folder:FindFirstChild("Beep3") }
		local rng = Random.new()
		for _ in string.gmatch(str, "%S+") do
			play(beeps[math.random(1, 3)], actor, function(sound)
				sound.PlaybackSpeed = rng:NextNumber(0.8, 1.15)
				sound.Volume = 0.6
			end)
			task.wait(0.035)
		end
	end,
}

local function effects(ctx)
	local actor = ctx.actor
	if actor:GetAttribute("FairyFlight") then
		local choices = {}
		local folder = dig(ReplicatedStorage, "Sounds.FairyChatSend")
		for _, sound in folder and folder:GetChildren() or {} do
			if sound:IsA("Sound") and sound.SoundId ~= "" then
				table.insert(choices, sound)
			end
		end
		if #choices > 0 then
			play(choices[math.random(1, #choices)], actor, function(sound)
				sound.PlaybackSpeed = math.random(95, 105) / 100
			end)
		end
	end
	local effect = sfx[ctx.mode]
	if effect then
		local ok, err = pcall(effect, ctx.str, actor)
		if not ok then
			log("language effect failed: " .. tostring(err))
		end
	end
end

local function yeet(nosyguy, adornee, str)
	if link and nosyguy.Parent == Players and str ~= "" then
		link:FireClient(nosyguy, "post", { Adornee = adornee, Text = str })
	end
end

local function deliver(nosyguy, ctx)
	if not reach(ctx.loudguy, nosyguy) then
		log("not sent to " .. nosyguy.Name .. ", their chat settings block it")
		return
	end
	local msg = prep(ctx.str, ctx)
	local ok, final = pcall(shape, nosyguy, ctx, msg)
	if not ok then
		final = msg
	end
	if not final then
		return
	end
	yeet(nosyguy, ctx.actor:FindFirstChild("Head") or ctx.actor, final)
end

local function pair(ctx)
	local captured = ctx.str:match("{(.-)}")
	local handler = ServerScriptService:FindFirstChild("MHandler")
	local pd = handler and handler:FindFirstChild("PD")
	if not captured or not names or not pd or pd.Value ~= true then
		return
	end
	local name = names.Clean(ctx.loudguy, captured)
	if not name then
		return
	end
	local count = 0
	for _, other in near(ctx.origin, math.min(opts.near, ctx.range)) do
		if other ~= ctx.loudguy and reach(ctx.loudguy, other) and names.Introduce(ctx.loudguy, other, name) then
			count += 1
		end
	end
	if count > 0 then
		notice(ctx.loudguy, "You introduced yourself as " .. name .. ".")
	end
end

local function post(ctx)
	local loudguy = ctx.loudguy
	local plain = ctx.str
	if plain:find("{.-}") then
		plain = plain:gsub("[{}]", "")
	end
	pcall(function()
		require(ServerScriptService.ServerModules.MindLink).Chat(loudguy, plain)
	end)
	local logs = ServerStorage:FindFirstChild("MessageLogs")
	if logs then
		local entry = Instance.new("StringValue")
		entry.Name = loudguy.Name .. " - Chat"
		entry:SetAttribute("Type", ctx.kind)
		local body = markup(escape(plain))
		if ctx.kind == "Whisper" then
			entry.Value = ctx.stamp .. " | (Whisper) " .. loudguy.Name .. ": " .. body
		elseif ctx.kind == "Thought" then
			entry.Value = ctx.stamp .. " | (Thought) " .. loudguy.Name .. ": " .. body
		else
			entry.Value = ctx.stamp .. " | " .. loudguy.Name .. ": " .. body
		end
		entry.Parent = logs
	end
	if ctx.kind == "Thought" then
		return
	end
	if ctx.origin then
		local ok, err = pcall(pair, ctx)
		if not ok then
			log("introduction failed: " .. tostring(err))
		end
	end
	local cam = workspace:FindFirstChild("TGACamera")
	local ce = fx()
	if not cam or not ce then
		return
	end
	if cam:GetAttribute("Global") == nil and not ctx.actor:FindFirstChild("TGA") then
		return
	end
	local focus = cam:FindFirstChild("Target")
	if not focus then
		focus = Instance.new("ObjectValue")
		focus.Name = "Target"
		focus.Parent = cam
	end
	focus.Value = ctx.actor
	local shown = prep(ctx.str, ctx)
	for _, other in Players:GetPlayers() do
		task.spawn(function()
			if reach(loudguy, other) then
				ce:FireClient(other, "Message", { Message = shown, Caller = loudguy, StyleType = "CharacterMessage" })
			end
		end)
	end
end

local function process(loudguy, str)
	local kind = "Normal"
	local low = str:lower()
	if low:sub(1, 3) == "/w " then
		kind = "Whisper"
		str = trim(str:sub(4))
	elseif low:sub(1, 3) == "/t " then
		kind = "Thought"
		str = trim(str:sub(4))
	end
	if str == "" or not utf8.len(str) then
		return
	end
	str = cut(str, opts.maxlen)
	local actor = owner(loudguy)
	if not actor then
		return
	end
	local root = actor:FindFirstChild("HumanoidRootPart")
	local own = loudguy.Character
	local active = kind ~= "Thought"
	local loudguydata = actor:FindFirstChild("PlayerData")
	local ctx = {
		loudguy = loudguy,
		mode = loudguydata and loudguydata:GetAttribute("CurrentLanguage") or "Default",
		kind = kind,
		str = str,
		actor = actor,
		origin = root and root.Position,
		range = kind == "Whisper" and opts.short or opts.range,
		stamp = stamp(),
		flagged = active and flagged(loudguy),
		down = active and own ~= nil and own:GetAttribute("Downed") == true,
		merry = active and (tonumber(loudguy:GetAttribute("Merriment")) or 0) or 0,
	}
	local ce = fx()
	if ctx.flagged and ce then
		ce:FireAllClients("GarbleStatic", { Character = actor })
	end
	local targets = { loudguy }
	if active and ctx.origin then
		for _, other in near(ctx.origin, ctx.range) do
			if other ~= loudguy then
				table.insert(targets, other)
			end
		end
	end
	log(loudguy.Name .. " " .. kind .. " to " .. #targets .. ": " .. str)
	for _, nosyguy in targets do
		task.spawn(deliver, nosyguy, ctx)
	end
	if active then
		task.spawn(effects, ctx)
	end
	task.spawn(post, ctx)
end

local function clearemote(char)
	for _, name in { "emote", "Emote", "CanUnanchor" } do
		local value = char:FindFirstChild(name)
		if value then
			value:Destroy()
		end
	end
end

local function emote(plr, msg)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if not anim then
		return
	end
	local emotes = dig(ReplicatedStorage, "Animations.Emotes")
	local words = string.split(msg, " ")
	local animation = emotes and emotes:FindFirstChild(string.lower(words[2] or ""))
	local alivedata = workspace:FindFirstChild("AliveData")
	local data = alivedata and alivedata:FindFirstChild(plr.Name)
	local status = data and data:FindFirstChild("Status")
	if animation and not char:GetAttribute("CuffBound") then
		local track = anim:LoadAnimation(animation)
		track:Play()
		track.Priority = Enum.AnimationPriority.Action3
		track.Name = "emote"
		if animation:GetAttribute("TrueStun") == true and status then
			local stun = Instance.new("StringValue")
			stun.Name = "Stun"
			stun.Parent = status
			local root = char:FindFirstChild("HumanoidRootPart")
			local first = root and root.Position
			local moving
			moving = RunService.Heartbeat:Connect(function()
				local cur = plr.Character
				local curroot = cur and cur:FindFirstChild("HumanoidRootPart")
				if not curroot or not stun.Parent or not first then
					moving:Disconnect()
					return
				end
				if (curroot.Position - first).Magnitude > 0.5 then
					moving:Disconnect()
					local curhum = cur:FindFirstChildOfClass("Humanoid")
					if curhum then
						for _, playing in curhum:GetPlayingAnimationTracks() do
							if playing.Name:find("emote") then
								playing:Stop()
							end
						end
					end
					stun:Destroy()
					clearemote(cur)
					curroot.Anchored = false
				end
			end)
			track.Ended:Once(function()
				moving:Disconnect()
				if stun.Parent then
					stun:Destroy()
				end
			end)
		elseif animation:GetAttribute("CantAttack") == true then
			local lock = Instance.new("StringValue")
			lock.Name = "CantAttack"
			lock.Parent = char
			if animation:GetAttribute("OneUse") then
				task.spawn(function()
					track.Ended:Wait()
					lock:Destroy()
					clearemote(char)
				end)
			end
		end
		if not char:FindFirstChild("emote") then
			local tag = Instance.new("StringValue")
			tag.Name = "emote"
			tag.Parent = char
		end
	end
	if msg:find("/e un") then
		local stopped = false
		for _, playing in hum:GetPlayingAnimationTracks() do
			if playing.Name:find("emote") then
				stopped = true
				playing:Stop()
			end
		end
		if stopped then
			if status then
				for _, value in status:GetChildren() do
					if value.Name == "Stun" then
						value:Destroy()
					end
				end
			end
			for _, name in { "Stun", "CantAttack" } do
				local value = char:FindFirstChild(name)
				if value then
					value:Destroy()
				end
			end
			clearemote(char)
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end
end

local function resolve(loudguy, word)
	word = (word or ""):lower()
	if word == "" or word == "me" or word == "self" then
		return { loudguy }
	end
	if word == "all" then
		return Players:GetPlayers()
	end
	if word == "others" then
		local list = {}
		for _, other in Players:GetPlayers() do
			if other ~= loudguy then
				table.insert(list, other)
			end
		end
		return list
	end
	local radius = word:match("^nearby#(%d+)$") or (word == "nearby" and "50")
	if radius then
		local root = loudguy.Character and loudguy.Character:FindFirstChild("HumanoidRootPart")
		return root and near(root.Position, tonumber(radius)) or {}
	end
	for _, other in Players:GetPlayers() do
		if other.Name:lower() == word or other.DisplayName:lower() == word then
			return { other }
		end
	end
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Name:lower():sub(1, #word) == word or other.DisplayName:lower():sub(1, #word) == word then
			table.insert(list, other)
		end
	end
	return list
end

local colors = {
	PSY = Color3.fromRGB(117, 86, 207),
	FYS = Color3.fromRGB(203, 71, 106),
	MOT = Color3.fromRGB(227, 183, 52),
	INT = Color3.fromRGB(92, 193, 215),
}

local jingles = {
	PSY = "rbxassetid://112138253041605",
	FYS = "rbxassetid://92176160113591",
	MOT = "rbxassetid://136681960041876",
	INT = "rbxassetid://139331195716884",
}

local function hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function runcmd(loudguy, name, args)
	local ce = fx()
	if not ce then
		return
	end
	local words = string.split(args, " ")
	local style = cmds[name]
	if type(style) == "string" then
		if args == "" then
			return
		end
		ce:FireAllClients("Message", { Message = args, Caller = loudguy, StyleType = style })
	elseif name == "notif" then
		local word = table.remove(words, 1)
		local msg = table.concat(words, " ")
		if not word or msg == "" then
			return
		end
		for _, plr in resolve(loudguy, word) do
			ce:FireClient(plr, "PMHolder", { Caller = plr, Message = msg })
		end
	elseif name == "snotif" then
		local word = words[1]
		local keyword = words[2] and words[2]:upper()
		local msg = table.concat(words, " ", 3)
		if not word or not colors[keyword or ""] or msg == "" then
			return
		end
		local now = os.time()
		for _, plr in resolve(loudguy, word) do
			local key = "LastSNotif_" .. keyword
			local jingle = (now - (plr:GetAttribute(key) or 0)) > 30
			if jingle then
				plr:SetAttribute(key, now)
			end
			ce:FireClient(plr, "SpecialNotif", { Caller = plr, Message = msg, Keyword = keyword, PlayJingle = jingle })
		end
	elseif name == "schat" then
		local word = table.remove(words, 1)
		local kind = table.remove(words, 1)
		local msg = table.concat(words, " ")
		if not word or not kind or msg == "" then
			return
		end
		local key = kind:upper()
		local rich = string.format('<font color="%s">%s</font>', hex(colors[key] or Color3.new(1, 1, 1)), markup(msg))
		for _, plr in resolve(loudguy, word) do
			local head = plr.Character and plr.Character:FindFirstChild("Head")
			if head then
				if jingles[key] then
					local sound = Instance.new("Sound")
					sound.SoundId = jingles[key]
					sound.Volume = 1
					sound.Parent = head
					sound:Play()
					Debris:AddItem(sound, 5)
				end
				for _, nosyguy in Players:GetPlayers() do
					yeet(nosyguy, head, rich)
				end
			end
		end
	end
	local logs = ServerStorage:FindFirstChild("CommandLogs")
	if logs then
		local entry = Instance.new("StringValue")
		entry.Name = loudguy.Name
		entry.Value = stamp() .. " | " .. loudguy.Name .. " - " .. name .. " " .. args
		entry.Parent = logs
	end
end

local function forward(plr, msg)
	local moderation = ServerScriptService:FindFirstChild("Moderation")
	local hook = moderation and moderation:FindFirstChild("playerChatted")
	if not hook then
		warn("link: command dropped")
		return false
	end
	local ok, res = pcall(hook.Invoke, hook, plr, msg)
	if not ok then
		warn("link: command failed: " .. tostring(res))
		return false
	end
	return res
end

local function route(plr, msg)
	if type(msg) ~= "string" then
		return false
	end
	local str = msg
	if str:sub(1, 1) == ";" then
		str = str:sub(2)
	end
	local name, args = str:match("^(%w+)%s+(.+)$")
	name = (name or str:match("^(%w+)") or ""):lower()
	if cmds[name] ~= nil and rank(plr) >= opts.rank then
		task.spawn(runcmd, plr, name, args or "")
		return true
	end
	return forward(plr, str)
end
mod.Route = route

local function submit(plr, str)
	if not on or type(str) ~= "string" then
		return
	end
	str = trim(str)
	if str == "" or not allow(plr) then
		return
	end
	if str:sub(1, 1) == ";" then
		task.spawn(route, plr, cut(str, opts.cmdlen))
	elseif str:lower():match("^/e%s+%S") then
		task.spawn(emote, plr, str)
	else
		task.spawn(process, plr, str)
	end
end
mod.Submit = submit

local function silence(gui)
	if not gui:IsA("ScreenGui") or gui:GetAttribute("linkoff") then
		return
	end
	gui:SetAttribute("linkoff", true)
	gui:SetAttribute("linkwasenabled", gui.Enabled)
	gui.Enabled = false
	for _, item in gui:GetDescendants() do
		if item:IsA("LocalScript") then
			item:SetAttribute("linkwasenabled", item.Enabled)
			item.Enabled = false
		end
	end
end

local function unsilence(gui)
	if not gui:GetAttribute("linkoff") then
		return
	end
	for _, item in gui:GetDescendants() do
		if item:IsA("LocalScript") and item:GetAttribute("linkwasenabled") ~= nil then
			item.Enabled = item:GetAttribute("linkwasenabled")
			item:SetAttribute("linkwasenabled", nil)
		end
	end
	gui.Enabled = gui:GetAttribute("linkwasenabled") ~= false
	gui:SetAttribute("linkwasenabled", nil)
	gui:SetAttribute("linkoff", nil)
end

local function give(plr, pgui)
	if not base then
		warn("link: Template not found")
		return
	end
	local old = pgui:FindFirstChild(opts.guiname)
	if old then
		old:Destroy()
	end
	local src = StarterGui:FindFirstChild("ExperienceChat") or pgui:FindFirstChild("ExperienceChat")
	local gui
	if src and src:IsA("ScreenGui") then
		gui = src:Clone()
		for _, child in gui:GetChildren() do
			if child:IsA("LocalScript") then
				child:Destroy()
			end
		end
		for _, item in gui:GetDescendants() do
			if item:IsA("LocalScript") then
				local was = item:GetAttribute("linkwasenabled")
				item.Enabled = was ~= false
				item:SetAttribute("linkwasenabled", nil)
			end
		end
		gui:SetAttribute("linkoff", nil)
		gui:SetAttribute("linkwasenabled", nil)
	else
		gui = Instance.new("ScreenGui")
	end
	gui.Name = opts.guiname
	gui.ResetOnSpawn = false
	gui.Enabled = true
	local client = base:Clone()
	client.Name = "DenDenMushi"
	client.Enabled = true
	client.Parent = gui
	gui.Parent = pgui
end

local function attach(plr)
	local pgui = plr:WaitForChild("PlayerGui", 15)
	if not pgui or not on then
		return
	end
	give(plr, pgui)
	for _, child in pgui:GetChildren() do
		if child.Name == "ExperienceChat" then
			silence(child)
		end
	end
	if watch[plr] then
		watch[plr]:Disconnect()
	end
	watch[plr] = pgui.ChildAdded:Connect(function(child)
		if child.Name == "ExperienceChat" then
			silence(child)
		end
	end)
end

local function forwarder(plr, msg)
	forward(plr, msg)
end

function mod.Start()
	if on then
		return false, "already on"
	end
	on = true
	local folder = remotes()
	if not folder then
		on = false
		warn("link: ReplicatedStorage.Remotes is missing, nothing changed")
		return false
	end
	link = folder:FindFirstChild(opts.linkname)
	if not link then
		link = Instance.new("RemoteEvent")
		link.Name = opts.linkname
		link.Parent = folder
	end
	table.insert(conns, link.OnServerEvent:Connect(function(plr, kind, str)
		if kind == "push" then
			submit(plr, str)
		end
	end))
	local requests = ReplicatedStorage:FindFirstChild("Requests")
	cmdlink = requests and requests:FindFirstChild("Command")
	if cmdlink and cmdlink:IsA("RemoteFunction") then
		cmdlink.OnServerInvoke = function(plr, msg)
			route(plr, msg)
		end
	else
		warn("link: couldn't find the command remote")
	end
	table.insert(conns, Players.PlayerAdded:Connect(function(plr)
		task.spawn(attach, plr)
	end))
	table.insert(conns, Players.PlayerRemoving:Connect(function(plr)
		rates[plr] = nil
		if watch[plr] then
			watch[plr]:Disconnect()
			watch[plr] = nil
		end
	end))
	for _, plr in Players:GetPlayers() do
		task.spawn(attach, plr)
	end
	print(`Enabled!`)
	return true
end

function mod.Stop()
	if not on then
		return false, "already off"
	end
	on = false
	for _, conn in conns do
		conn:Disconnect()
	end
	table.clear(conns)
	for _, conn in watch do
		conn:Disconnect()
	end
	table.clear(watch)
	if cmdlink and cmdlink.Parent then
		cmdlink.OnServerInvoke = forwarder
	end
	if link then
		link:FireAllClients("stop")
	end
	for _, plr in Players:GetPlayers() do
		local pgui = plr:FindFirstChildOfClass("PlayerGui")
		if pgui then
			for _, child in pgui:GetChildren() do
				if child.Name == "ExperienceChat" then
					unsilence(child)
				end
			end
			local ours = pgui:FindFirstChild(opts.guiname)
			if ours then
				task.delay(1, function()
					if ours.Parent then
						ours:Destroy()
					end
				end)
			end
		end
	end
	local old = link
	link = nil
	task.delay(3, function()
		if old and old.Parent and not on then
			old:Destroy()
		end
	end)
	print("link is disabled")
	return true
end

mod.Start()

return mod
