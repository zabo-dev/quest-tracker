-- Quest Share: writes a small file with only quest progress (no gold, bags or gear),
-- so it can be uploaded and compared with a friend's. Data comes from the WarlockPath addon.
local function newest()
  local db = WarlockPathDB
  if not (db and db.chars) then return nil end
  local best
  for _, c in pairs(db.chars) do
    if type(c) == "table" and c.t and (not best or c.t > best.t) then best = c end
  end
  return best
end

local function copy()
  local c = newest()
  if not c then return end
  local quests = {}
  for _, q in ipairs(c.quests or {}) do
    quests[#quests + 1] = { id = q.id, title = q.title, level = q.level, zone = q.zone, complete = q.complete, obj = q.obj }
  end
  QuestShareDB = {
    schema = 1, t = c.t, name = c.name, level = c.level, xp = c.xp, xpMax = c.xpMax,
    class = c.class, race = c.race, faction = c.faction, zone = c.zone,
    quests = quests, questsDone = c.questsDone, questsDoneList = c.questsDoneList, turnins = c.turnins,
  }
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", copy)
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(20, copy) end
