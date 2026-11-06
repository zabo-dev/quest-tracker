-- Warlock's Path: writes a snapshot of this character into WarlockPathDB.
-- WoW only writes SavedVariables to disk on /reload or logout, so that's when the website sees new data.

local ADDON = ...
local SCHEMA = 2

-- market items the website tracks (item IDs); prices for these and for everything in your bags are saved
local TRACKED = {
  248682, 248683, 248684, 248686, 248687, 248688, 248690, 248691, 248692, 248693,
  2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 12359, 12363, 12360,
  2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,
  2589, 2592, 4306, 4338, 14047, 14256, 14342, 2996, 2997, 4305, 4339, 14048,
  2318, 2319, 4234, 4304, 8170, 15417, 14344, 16204, 7078, 12808, 7068,
  118, 858, 929, 1710, 3928, 13446, 3385, 13443, 13444, 8949, 8951, 9154, 9187, 9264, 13454, 13512, 13457, 13459, 12662, 20749,
  4238, 2580, 2587, 4314, 7048, 7050, 4334, 7058, 7062, 9999, 10003, 10024, 13856, 13863, 14046,
  1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530,
}

local INV_SLOTS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
  [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand",
  [18] = "Ranged", [19] = "Tabard",
}

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
-- the Forever client moved GetItemInfo into C_Item
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
-- some combat numbers are "secret values" on this client: addons may not compare or store them, so drop those
local function num(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok, r = pcall(function() return v + 0 end)
  return ok and r or nil
end

-- item facts the website needs to judge an item for a Warlock: armor type, slot, stats, vendor price
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local STAT_KEYS = {
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_SPELL_POWER_SHORT = "sp",
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
  ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE0_NAME = "armor", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
}
local detailCache = {}
local function itemDetail(link)
  if not link then return nil end
  local key = link:match("item:[%-?%d:]+") or link
  if detailCache[key] then return detailCache[key] end
  local name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = ItemInfo(link)
  if not name then return nil end  -- not cached by the client yet; try again next snapshot
  local d = { id = tonumber(link:match("item:(%d+)")), name = name, q = num(quality), il = num(ilvl), req = num(reqLevel),
    loc = (equipLoc ~= "" and not tostring(equipLoc):find("NON_EQUIP")) and equipLoc or nil, sell = num(sellPrice), cls = num(classID), sub = num(subclassID) }
  if d.loc then
    local ok, stats = pcall(GetStats, link)
    if ok and type(stats) == "table" then
      d.st = {}
      for k, v in pairs(stats) do
        local short = STAT_KEYS[k]
        if short then d.st[short] = (d.st[short] or 0) + (num(v) or 0) end
      end
    end
  end
  detailCache[key] = d
  return d
end

local function linkInfo(link)
  if not link then return nil end
  return tonumber(link:match("item:(%d+)")), link:match("%[(.-)%]")
end

local function slotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then
      local _, name = linkInfo(info.hyperlink)
      return info.itemID, info.stackCount or 1, name
    end
  elseif GetContainerItemInfo then
    local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
    if link then
      local id, name = linkInfo(link)
      return id, count or 1, name
    end
  end
end

local function slotLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
  if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
end

local function scanBags(bags)
  local totals, names, links = {}, {}, {}
  for _, bag in ipairs(bags) do
    for slot = 1, (GetNumSlots(bag) or 0) do
      local id, count, name = slotItem(bag, slot)
      if id then
        totals[id] = (totals[id] or 0) + count
        names[id] = name
        links[id] = links[id] or slotLink(bag, slot)
      end
    end
  end
  local list = {}
  for id, n in pairs(totals) do
    local e = { id = id, n = n, name = names[id] }
    local ok, d = pcall(itemDetail, links[id])
    if ok and d and d.loc then e.d = d end  -- only equippable items carry details
    list[#list + 1] = e
  end
  return list
end

local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function stats()
  local s = {
    health = num(UnitHealthMax("player")),
    mana = num(UnitPowerMax("player", 0)),
  }
  local keys = { "strength", "agility", "stamina", "intellect", "spirit" }
  for i, k in ipairs(keys) do
    local _, effective = UnitStat("player", i)
    s[k] = num(effective)
  end
  local _, armor = UnitArmor("player")
  s.armor = num(armor)
  if GetSpellBonusDamage then
    local low
    for school = 2, 7 do
      local v = num(GetSpellBonusDamage(school))
      if v and (not low or v < low) then low = v end
    end
    s.spell_damage = low
    s.shadow_damage = num(GetSpellBonusDamage(6))
  end
  if GetSpellCritChance then s.spell_crit_pct = num(GetSpellCritChance(6)) end
  if GetSpellHitModifier then s.spell_hit_pct = num(GetSpellHitModifier()) end
  return s
end

local function gear()
  local list = {}
  for slot = 1, 19 do
    local id, name = linkInfo(GetInventoryItemLink("player", slot))
    if id then
      local link = GetInventoryItemLink("player", slot)
      local ok, d = pcall(itemDetail, link)
      d = ok and d or {}
      list[#list + 1] = { slot = INV_SLOTS[slot], id = id, name = name, q = d.q, il = d.il, d = d.id and d or nil }
    end
  end
  return list
end

local function skills()
  local list = {}
  WarlockPathDB.skillApi = { lines = GetNumSkillLines and true or false, profs = GetProfessions and true or false,
    skillLine = C_SkillLine and true or false, tradeSkill = C_TradeSkillUI and true or false }
  local header
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
      if isHeader then header = name
      elseif name then list[#list + 1] = { name = name, rank = num(rank), max = num(max), cat = header } end
    end
  end
  -- newer clients (the Forever beta) only expose professions through GetProfessions
  if #list == 0 and GetProfessions then
    for _, idx in pairs({ GetProfessions() }) do
      local name, _, rank, max = GetProfessionInfo(idx)
      if name then list[#list + 1] = { name = name, rank = num(rank), max = num(max) } end
    end
  end
  return list
end

-- ---------- quest log ----------
local function objectivesFor(questID, index)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and objs then
      for _, o in ipairs(objs) do out[#out + 1] = { text = o.text, done = o.finished and true or false } end
      if #out > 0 then return out end
    end
  end
  if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and index then
    for j = 1, (GetNumQuestLeaderBoards(index) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(j, index)
      if text then out[#out + 1] = { text = text, done = finished and true or false } end
    end
  end
  return out
end

local rewardCache = {}
local function questRewards(index, questID)
  if questID and rewardCache[questID] then return rewardCache[questID] end
  local out = { choice = {}, fixed = {} }
  local prev = GetQuestLogSelection and GetQuestLogSelection()
  if SelectQuestLogEntry and index then SelectQuestLogEntry(index) end
  local nc = (GetNumQuestLogChoices and GetNumQuestLogChoices(questID)) or 0
  local nr = (GetNumQuestLogRewards and GetNumQuestLogRewards(questID)) or 0
  local complete = true
  for j = 1, nc do
    local d = GetQuestLogItemLink and itemDetail(GetQuestLogItemLink("choice", j))
    if d then out.choice[#out.choice + 1] = d else complete = false end
  end
  for j = 1, nr do
    local d = GetQuestLogItemLink and itemDetail(GetQuestLogItemLink("reward", j))
    if d then out.fixed[#out.fixed + 1] = d else complete = false end
  end
  out.money = GetQuestLogRewardMoney and num(GetQuestLogRewardMoney(questID)) or nil
  if SelectQuestLogEntry and prev and prev > 0 then SelectQuestLogEntry(prev) end
  if questID and complete then rewardCache[questID] = out end
  return out
end

local function questLog()
  local list, header = {}, nil
  if GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
      if isHeader then header = title
      elseif title then
        local okR, rew = pcall(questRewards, i, questID)
        list[#list + 1] = { id = questID, title = title, level = level, zone = header,
          complete = (isComplete == 1 or isComplete == true) and true or false, obj = objectivesFor(questID, i), rew = okR and rew or nil }
      end
    end
  elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local q = C_QuestLog.GetInfo(i)
      if q and q.isHeader then header = q.title
      elseif q and q.title then
        local okR, rew = pcall(questRewards, i, q.questID)
        list[#list + 1] = { id = q.questID, title = q.title, level = q.level, zone = header,
          complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID) or false, obj = objectivesFor(q.questID, i), rew = okR and rew or nil }
      end
    end
  end
  return list
end

-- newer clients store talents as "traits" (C_ClassTalents / C_Traits) instead of talent tabs
local function spellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function traitTalents()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil end
  local cfg = C_Traits.GetConfigInfo(configID)
  local out, list = {}, {}
  for _, treeID in ipairs((cfg and cfg.treeIDs) or {}) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      local rank = node and num(node.activeRank) or 0
      if node and rank > 0 then
        local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
        local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
        local name = def and (def.overrideName or spellName(def.spellID)) or ("Node " .. nodeID)
        list[#list + 1] = { name = name, rank = rank, max = num(node.maxRanks), spell = def and def.spellID }
      end
    end
  end
  local points = 0
  for _, t in ipairs(list) do points = points + t.rank end
  out[1] = { name = "Talente", points = points, list = list }
  return out
end

local function talents()
  WarlockPathDB.talentApi = { tabs = GetNumTalentTabs and true or false, traits = (C_ClassTalents and C_Traits) and true or false }
  if not (GetNumTalentTabs and GetTalentInfo) or (GetNumTalentTabs() or 0) == 0 then return traitTalents() end
  local out = {}
  for t = 1, GetNumTalentTabs() do
    local a, b, c = GetTalentTabInfo(t)
    local tab = { name = type(a) == "string" and a or (type(b) == "string" and b) or ("Tree " .. t), points = 0, list = {} }
    for i = 1, (GetNumTalents(t) or 0) do
      local name, _, tier, column, rank, maxRank = GetTalentInfo(t, i)
      rank = num(rank) or 0
      if name and rank > 0 then tab.list[#tab.list + 1] = { name = name, rank = rank, max = num(maxRank), tier = num(tier), col = num(column) } end
      tab.points = tab.points + rank
    end
    out[#out + 1] = tab
  end
  return out
end

-- spells you know, highest rank per name (modern C_SpellBook first, classic spell tabs as fallback)
local function spellbook()
  local byName = {}
  local function add(name, sub, spellID)
    if not name then return end
    local rank = tonumber((sub or ""):match("(%d+)")) or 0
    local e = byName[name]
    if not e or rank > (e.rank or 0) then byName[name] = { name = name, rank = rank > 0 and rank or nil, id = spellID } end
  end
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if line and not line.shouldHide then
        for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
          local info = C_SpellBook.GetSpellBookItemInfo(j, bank)
          if info and info.name and not info.isPassive and info.itemType ~= (Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) then
            add(info.name, info.subName, info.spellID)
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo then
    for i = 1, GetNumSpellTabs() do
      local _, _, offset, numSpells = GetSpellTabInfo(i)
      for j = offset + 1, offset + numSpells do
        local name, sub = GetSpellBookItemName(j, BOOKTYPE_SPELL or "spell")
        local _, id = GetSpellBookItemInfo(j, BOOKTYPE_SPELL or "spell")
        add(name, sub, id)
      end
    end
  end
  local list = {}
  for _, e in pairs(byName) do list[#list + 1] = e end
  return list
end

local function completedQuests()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and list then for _, id in ipairs(list) do ids[#ids + 1] = id end end
  elseif GetQuestsCompleted then
    for id in pairs(GetQuestsCompleted() or {}) do ids[#ids + 1] = id end
  end
  local out = {}
  for _, id in ipairs(ids) do
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    out[#out + 1] = { id = id, title = title }
  end
  return out
end

local function completedCount()
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and ids then return #ids end
  end
  if GetQuestsCompleted then
    local t, n = GetQuestsCompleted(), 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
  end
end

-- ---------- ledger: real AH sales/purchases (from mailbox invoices) and crafts ----------
local function ledger()
  WarlockPathDB = WarlockPathDB or {}
  WarlockPathDB.ledger = WarlockPathDB.ledger or {}
  WarlockPathDB.ledgerKeys = WarlockPathDB.ledgerKeys or {}
  return WarlockPathDB.ledger, WarlockPathDB.ledgerKeys
end

local function addEntry(e, key)
  local list, keys = ledger()
  if key then
    if keys[key] then return end
    keys[key] = true
  end
  e.char = charKey()
  list[#list + 1] = e
  while #list > 2000 do table.remove(list, 1) end
end

local function idByName(name)
  local _, link = ItemInfo(name)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

local function scanInvoices()
  if not (GetInboxNumItems and GetInboxInvoiceInfo) then return end
  local _, keys = ledger()
  for i = 1, GetInboxNumItems() do
    local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
    local kind, itemName, player, bid, _, _, cut = GetInboxInvoiceInfo(i)
    if (kind == "seller" or kind == "buyer") and itemName and bid then
      local qty = tonumber((subject or ""):match("%((%d+)%)%s*$")) or 1
      -- AH mail lasts 30 days, so this gives a stable receive time for de-duplication
      local recv = time() - math.floor((30 - (daysLeft or 30)) * 86400)
      local base = kind .. "|" .. itemName .. "|" .. bid .. "|" .. qty .. "|"
      local hour = math.floor(recv / 3600)
      if not (keys[base .. (hour - 1)] or keys[base .. (hour + 1)]) then
        addEntry({ t = recv, kind = kind == "seller" and "sell" or "buy", id = idByName(itemName), name = itemName,
                   qty = qty, copper = bid, cut = cut or 0, player = player, src = "ah" }, base .. hour)
      end
    end
  end
end

local function onTradeskill(msg)
  local link = msg and msg:match("|H(item:%d+.-)|h")
  local prefix = TRADESKILL_LOG_FIRSTPERSON and TRADESKILL_LOG_FIRSTPERSON:match("^(.-)%%s") or "You create"
  if not link or not msg:find(prefix, 1, true) then return end
  local id = tonumber(link:match("item:(%d+)"))
  local qty = tonumber(msg:match("|rx(%d+)")) or tonumber(msg:match("x(%d+)%.?$")) or 1
  addEntry({ t = time(), kind = "craft", id = id, name = msg:match("%[(.-)%]"), qty = qty, src = "craft" })
end

local function auctionatorPrices(bagItems)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return nil end
  local prices, seen = {}, {}
  local function add(id)
    if seen[id] then return end
    seen[id] = true
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
    if ok and price and price > 0 then prices[#prices + 1] = { id = id, copper = price } end
  end
  for _, id in ipairs(TRACKED) do add(id) end
  for _, it in ipairs(bagItems) do add(it.id) end
  return prices
end

-- the client reports zeros while loading and during logout, so only trust a live, loaded character
local function charReady()
  return UnitLevel("player") > 0 and (UnitHealthMax("player") or 0) > 0 and ((UnitXPMax("player") or 0) > 0 or UnitLevel("player") >= 60)
end

-- one failing API on a new client must never block the whole snapshot: run each part protected and log errors
local function safe(name, fn, ...)
  local ok, res = pcall(fn, ...)
  if ok then return res end
  WarlockPathDB = WarlockPathDB or {}
  WarlockPathDB.errors = WarlockPathDB.errors or {}
  WarlockPathDB.errors[name] = { t = time(), msg = tostring(res) }
  return nil
end

local function snapshot(withPrices)
  WarlockPathDB = WarlockPathDB or {}
  local okReady, ready = pcall(charReady)
  WarlockPathDB.debug = { t = time(), ready = okReady and ready or false, level = UnitLevel("player"),
    xpMax = UnitXPMax("player"), hp = UnitHealthMax("player"), version = "1.6.0", missing = WarlockPathMissingEvents }
  if not (okReady and ready) then
    -- keep the last good snapshot, only refresh prices if asked
    local c = WarlockPathDB and WarlockPathDB.chars and WarlockPathDB.chars[charKey()]
    if c and withPrices then
      c.prices = auctionatorPrices(c.bags or {}) or c.prices
      c.pricesT = (Auctionator and time()) or c.pricesT
    end
    return
  end
  WarlockPathDB = WarlockPathDB or {}
  WarlockPathDB.schema = SCHEMA
  WarlockPathDB.chars = WarlockPathDB.chars or {}
  local key = charKey()
  local prev = WarlockPathDB.chars[key] or {}
  local bags = safe("bags", scanBags, { 0, 1, 2, 3, 4 }) or prev.bags or {}
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  WarlockPathDB.chars[key] = {
    t = time(),
    name = UnitName("player"),
    realm = GetRealmName(),
    faction = UnitFactionGroup("player"),
    race = race,
    class = class,
    level = UnitLevel("player"),
    xp = UnitXP("player"),
    xpMax = UnitXPMax("player"),
    rested = GetXPExhaustion() or 0,
    money = GetMoney(),
    zone = GetZoneText(),
    stats = safe("stats", stats) or prev.stats,
    gear = safe("gear", gear) or prev.gear,
    bags = bags,
    bank = prev.bank,
    bankT = prev.bankT,
    skills = safe("skills", skills) or prev.skills,
    quests = safe("quests", questLog) or prev.quests,
    talents = safe("talents", talents) or prev.talents,
    spells = safe("spells", spellbook) or prev.spells,
    pet = UnitExists and UnitExists("pet") and { name = UnitName("pet"), family = UnitCreatureFamily and UnitCreatureFamily("pet"), level = num(UnitLevel("pet")) } or nil,
    talentPts = num(UnitCharacterPoints and UnitCharacterPoints("player")),
    questsDone = safe("questsDone", completedCount) or prev.questsDone,
    questsDoneList = safe("questsDoneList", completedQuests) or prev.questsDoneList,
    turnins = WarlockPathDB.turnins,
    prices = (withPrices and safe("prices", auctionatorPrices, bags)) or prev.prices,
    pricesT = (withPrices and Auctionator and time()) or prev.pricesT,
  }
end

local f = CreateFrame("Frame")
-- register each event on its own: an event name this client doesn't know must not stop the addon from loading
for _, ev in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "QUEST_LOG_UPDATE", "BANKFRAME_OPENED", "MAIL_INBOX_UPDATE", "CHAT_MSG_TRADESKILLS" }) do
  if not pcall(f.RegisterEvent, f, ev) then
    WarlockPathMissingEvents = (WarlockPathMissingEvents or "") .. ev .. " "
  end
end
-- keep a fresh snapshot while you play (at most every 3 seconds); the next /reload or logout writes it to disk
local pending = false
local function soon()
  if pending then return end
  pending = true
  C_Timer.After(3, function() pending = false; safe("snapshot", snapshot, false) end)
end
pcall(f.RegisterEvent, f, "QUEST_TURNED_IN")
local titleCache = {}
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "QUEST_TURNED_IN" then
    WarlockPathDB.turnins = WarlockPathDB.turnins or {}
    local title = titleCache[arg1] or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(arg1))
    WarlockPathDB.turnins[#WarlockPathDB.turnins + 1] = { id = arg1, title = title, t = time(), level = UnitLevel("player") }
    soon()
  elseif event == "QUEST_LOG_UPDATE" then
    local c = WarlockPathDB.chars and WarlockPathDB.chars[charKey()]
    for _, q in ipairs((c and c.quests) or {}) do if q.id then titleCache[q.id] = q.title end end
    soon()
  elseif event == "PLAYER_LOGOUT" then
    safe("snapshot", snapshot, true)
  elseif event ~= "MAIL_INBOX_UPDATE" and event ~= "CHAT_MSG_TRADESKILLS" and event ~= "BANKFRAME_OPENED" then
    soon()
  elseif event == "MAIL_INBOX_UPDATE" then
    scanInvoices()
  elseif event == "CHAT_MSG_TRADESKILLS" then
    onTradeskill(arg1)
  elseif event == "BANKFRAME_OPENED" then
    WarlockPathDB = WarlockPathDB or {}
    WarlockPathDB.chars = WarlockPathDB.chars or {}
    local c = WarlockPathDB.chars[charKey()] or {}
    c.bank = scanBags({ -1, 5, 6, 7, 8, 9, 10 })
    c.bankT = time()
    WarlockPathDB.chars[charKey()] = c
  end
end)

-- safety net: refresh the snapshot every 15 seconds even if some events never fire on this client
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, function() safe("snapshot", snapshot, false) end) end

SLASH_WARLOCKPATH1 = "/wp"
SlashCmdList.WARLOCKPATH = function(msg)
  msg = (msg or ""):lower()
  if msg == "sync" then
    safe("snapshot", snapshot, true)
    ReloadUI()
  elseif msg == "status" then
    local d = WarlockPathDB and WarlockPathDB.debug
    print("|cff8f90f0Warlock's Path|r 1.3.0: last snapshot " .. (d and date("%H:%M:%S", d.t) or "never") .. (d and (" · ready " .. tostring(d.ready)) or "") .. (WarlockPathMissingEvents and (" · unknown events: " .. WarlockPathMissingEvents) or ""))
    if WarlockPathDB and WarlockPathDB.errors then for k, e in pairs(WarlockPathDB.errors) do print("  " .. k .. ": " .. e.msg) end end
  else
    print("|cff8f90f0Warlock's Path|r: |cfff5c542/wp sync|r sends your data to the website, |cfff5c542/wp status|r shows if it works.")
  end
end
