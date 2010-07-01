--[[
Copyright (c) 2009, Chris Bannister
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    * Neither the name of the <ORGANIZATION> nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[
--Track that Combat Yo!
--
--Is in combat when:
--	Group has hit mobs, theyre not dead yet.
--	A mob is aggrod.
--	done damage in the past 5 seconds and the mob isnt dead.
]]
local lib = LibStub and LibStub:NewLibrary("IdHitThat-1.0", 1)

if(not lib) then
	return
end

--[[
local R = LibStub("ZeeRoster-1.0")

if(not R) then
	return error("WE REQUIRE ZEEROSTER")
end
]]

local UnitExists = UnitExists
local UnitInRaid = UnitInRaid
local UnitGUID = UnitGUID

-- Combat time update, when they got hit, hit.
local lastUpdate = {}
local lastHit = {}
-- mobs -> { players }
local agro = {}
-- players -> { mobs }
local combatants = {}

local raid_combat = false

--[[
	EVENTS
]]

local damage_events = {
	["SWING_DAMAGE"] = true,
	["SPELL_DAMAGE"] = true,
	["SPELL_PERIODIC_DAMAGE"] = true,
	["RANGE_DAMAGE"] = true,
}

local healing_events = {
	["SPELL_HEAL"] = true,
	["SPELL_PERIODIC_HEAL"] = true,
}

local f = CreateFrame("Frame")

f:SetScript("OnEvent", function(self, event, ...)
	return self[event](self, ...)
end)

f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
local friend_filter = bit.bor(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)
local hostile_filter = bit.bor(COMBATLOG_OBJECT_REACTION_NEUTRAL, COMBATLOG_OBJECT_REACTION_HOSTILE)

function f:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	if(bit.band(sourceFlags, friend_filter) > 0) then
		-- Are we doing damage, or healing?
		if(damage_events[event] and bit.band(destFlags, hostile_filter) > 0) then
			raid_combat = true

			if(not agro[destGUID]) then
				agro[destGUID] = {}
			end

			if(not combatants[sourceGUID]) then
				combatants[sourceGUID] = {}
			end

			table.insert(agro[destGUID], sourceGUID)
			table.insert(combatants[sourceGUID], destGUID)

			lastUpdate[sourceGUID] = timeStamp
		elseif(healing_events[event] and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) > 0) then
			-- is the dest in combat?
			if(combatants[destGUID] and #combatants[destGUID] > 0) then
				raid_combat = true

				-- For time being healer is locked in combat
				-- by the mob the person he healed is in
				-- combat with
				if(combatants[destGUID] and #combatants[destGUID] > 0) then
					combatants[sourceGUID] = combatants[sourceGUID] or {}
					for k, v in pairs(combatants[destGUID]) do
						table.insert(combatants[sourceGUID], v)
					end
				end

				lastUpdate[sourceGUID] = timeStamp
			end
		elseif(event == "UNIT_DIED") then
			-- friendly death
			if(combatants[sourceGUID]) then
				for k, v in pairs(combatants[sourceGUID]) do
					if(agro[k] and #agro[k] > 0) then
						for i = 1, #agro[k] do
							if(agro[k][i] == sourceGUID) then
								agro[k][i] = nil
							end
						end

						if not(#agro[k] > 0) then
							agro[k] = nil
						end
					end
				end

				combatants[sourceGUID] = nil
			end

			if not(#combatants > 0) then
				raid_combat = false
			end
		else
			return
		end
	elseif(bit.band(sourceFlags, hostile_filter) > 0) then
		if(damage_events[event] and bit.band(destFlags, friend_filter) > 0) then
			-- Someone got hit, oh fux!
			if(not agro[sourceGUID]) then
				agro[souceGUID] = {}
			end

			if(not combatants[destGUID]) then
				combatants[destGUID] = {}
			end

			table.insert(agro[sourceGUID], destGUID)
			table.insert(combatants[destGUID], sourceGUID)

			lastHit[destGUID] = timestamp
		elseif(event == "UNIT_DIED") then
			-- Enemy death
			if(agro[sourceGUID]) then
				for k, v in pairs(agro[sourceGUID]) do
					if(combatants[k] and #combatants[k] > 0) then
						for i = 1, #combatants[k] do
							if(combatants[k][i] == sourceGUID) then
								combatants[k][i] = nil
							end
						end

						if not(#combatants[k] > 0) then
							combatants[k] = nil
						end
					end
				end

				agro[sourceGUID] = nil
			end

			if not(#agro > 0) then
				raid_combat = false
			end
		end
	else
		return
	end
end

function f:ZONE_CHANGED_NEW_AREA()
	for k, v in pairs(agro) do
		for i = 1, #agro[k] do
			agro[k][i] = nil
		end
		agro[k] = nil
	end

	for k, v in pairs(combatants) do
		for i = 1, #combatants[k] do
			combatants[k][i] = nil
		end
		combatants[k] = nil
	end
end

--[[
	HELPERS
]]

local hasAgro = function(guid)
	if(agro[guid] and #agro[guid] > 0) then
		return true
	else
		return false
	end
end

local timeout = function(guid)
	local time = time()

	if((time - (lastHit[guid] or 0) > 5) and (time - (lastUpdate[guid] or 0) > 5) and hasAgro(guid)) then
		return true
	else
		return false
	end
end

--[[
	PUBLIC API
]]

function lib:RaidInCombat()
	local combat = false

	if(#combatants > 0) then
		for k, v in pairs(combatants) do
			if(not timeout(guid)) then
				combat = true
				break
			end
		end
	end


	raid_combat = combat

	return combat
end

function lib:InCombat(guid)
	if(timeout(guid)) then
		-- They are out of combat. Should really check if the rest of
		-- the raid is in combat tho.
		return false
	end

	if(self:RaidInCombat()) then
		return true
	end

	-- Memory leak :E
	if(#combatants[guid] > 0) then
		return true
	end

	return false
end
