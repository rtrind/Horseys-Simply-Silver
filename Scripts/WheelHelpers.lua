WheelHelpers = {}

local AwardMap = {
	["StageAward_FullComboW1"] = 1,
	["StageAward_FullComboW2"] = 2,
	["StageAward_SingleDigitW2"] = 2,
	["StageAward_OneW2"] = 2,
	["StageAward_FullComboW3"] = 3,
	["StageAward_SingleDigitW3"] = 3,
	["StageAward_OneW3"] = 3,
	["StageAward_100PercentW3"] = 3,
	["StageAward_FullComboW4"] = 4,
}

function WheelHelpers.GetLamp(song, player)
	if not song then return nil end
	
	local pn = ToEnumShortString(player)
	if not GAMESTATE:IsPlayerEnabled(player) then return nil end
	
	-- Get current steps for this player to match difficulty
	local currentSteps = GAMESTATE:GetCurrentSteps(player)
	if not currentSteps then return nil end
	
	local diff = currentSteps:GetDifficulty()
	local st = GAMESTATE:GetCurrentStyle():GetStepsType()
	
	-- Find steps in song matching current difficulty
	local steps = nil
	local stepsList = song:GetAllSteps()
	for check in ivalues(stepsList) do
		if check:GetDifficulty() == diff and check:GetStepsType() == st then
			steps = check
			break
		end
	end
	
	if steps == nil then return nil end
	
	local profile = PROFILEMAN:GetProfile(player)
	local high_score_list = profile:GetHighScoreListIfExists(song, steps)

	if high_score_list == nil or #high_score_list:GetHighScores() == 0 then
		return nil
	end

	local best_lamp = nil
	local tap_count = 99
	local best_grade = nil

    Trace("WheelHelpers: Checking song " .. tostring(song:GetMainTitle()) .. " for " .. tostring(pn) .. " | Diff: " .. tostring(diff))

	for score in ivalues(high_score_list:GetHighScores()) do
		local award = score:GetStageAward()
		local grade = score:GetGrade()

		-- Check for pseudo-FC (W4 FC)
		if award == nil and SL.Global.GameMode == "FA+" and grade ~= "Grade_Failed" then
			local misses = score:GetTapNoteScore("TapNoteScore_Miss") +
					score:GetHoldNoteScore("HoldNoteScore_LetGo") +
					score:GetTapNoteScore("TapNoteScore_CheckpointMiss")
			if misses + score:GetTapNoteScore("TapNoteScore_W5") == 0 then
				award = "StageAward_FullComboW4"
			end
		end
		
		if award and AwardMap[award] ~= nil then
			if best_lamp ~= nil and AwardMap[award] < best_lamp then
				tap_count = 99
			end
			best_lamp = math.min(best_lamp and best_lamp or 999, AwardMap[award])
		end
		
		-- Single Digit Judge Count
		if AwardMap[award] == best_lamp then
			if best_lamp == 1 and score:GetScore() > 0 then
				tap_count = math.min(tap_count, score:GetScore())
			elseif best_lamp == 2 then
				tap_count = math.min(tap_count, score:GetTapNoteScore("TapNoteScore_W2"))
			elseif best_lamp == 3 then
				tap_count = math.min(tap_count, score:GetTapNoteScore("TapNoteScore_W3"))
			end
		end
		
		if AwardMap[award] == best_lamp and best_lamp == 1 and score:GetScore() == 0 then
			best_lamp = 0
		elseif best_lamp == nil then
			if grade == "Grade_Failed" then best_lamp = 52
			else best_lamp = 51 end
		end

        -- Track best grade (HIGHER enum value is BETTER grade)
        -- Grade enum: Grade_Tier01 (AAAA) < ... < Grade_Tier17 (D) < Grade_Failed
        -- So we want the MAXIMUM grade value (best performance)
        local prev_best = best_grade
        if best_grade == nil then
            best_grade = grade
        elseif grade ~= nil and grade > best_grade then
            best_grade = grade
        end
        Trace("WheelHelpers: Score Grade: " .. tostring(grade) .. " | Best was: " .. tostring(prev_best) .. " | Best is now: " .. tostring(best_grade))
	end

    Trace("WheelHelpers: Final Best Grade for " .. tostring(song:GetMainTitle()) .. ": " .. tostring(best_grade))
	return best_lamp, tap_count, best_grade
end

