describe("Trade upgrade recommendations", function()
	local tradeQuery
	local itemsTab

	local function item(name, itemType, baseName, subType)
		return {
			name = name,
			type = itemType,
			baseName = baseName or name,
			base = {
				type = itemType,
				subType = subType,
				tags = { },
			},
		}
	end

	local function slot(slotName, selItemId, shown)
		return {
			slotName = slotName,
			label = slotName,
			selItemId = selItemId or 0,
			inactive = shown == false,
			shown = function()
				return shown ~= false
			end,
			IsShown = function(self)
				return self.shown()
			end,
		}
	end

	local function mockWeight(baseOutput, newOutput, statWeights)
		local score = 0
		for _, stat in ipairs(statWeights) do
			local base = baseOutput[stat.stat] or 0
			local new = newOutput[stat.stat] or 0
			score = score + (new / (base ~= 0 and base or 1)) * stat.weightMult
		end
		return score
	end

	before_each(function()
		itemsTab = {
			items = { },
			slots = { },
			orderedSlots = { },
			sockets = { },
			leagueDropList = { "Standard" },
			build = {
				calcsTab = {
					GetMiscCalculator = function()
						return function()
							return { TotalDPS = 100 }
						end, { TotalDPS = 100 }
					end,
				},
			},
			CopyAnointsAndAugments = function() end,
		}
		tradeQuery = new("TradeQuery", itemsTab)
		tradeQuery.statSortSelectionList = { { label = "DPS", stat = "TotalDPS", weightMult = 1 } }
		tradeQuery.tradeQueryGenerator = {
			WeightedRatioOutputs = mockWeight,
		}
	end)

	it("builds eligible slot rows from gear and active jewel sockets", function()
		itemsTab.items[1] = item("Mace", "One Hand Mace", "Clasped Sceptre")
		itemsTab.items[2] = item("Swap Mace", "One Hand Mace", "Clasped Sceptre")
		itemsTab.items[3] = item("Robe", "Body Armour", "Elementalist Robe")
		itemsTab.items[4] = item("Charm", "Charm", "Charm")
		itemsTab.items[5] = item("Life Flask", "Flask", "Life Flask")
		itemsTab.items[6] = item("Unsupported", "Unknown", "Unknown")
		itemsTab.items[7] = item("Socketed Jewel", "Jewel", "Ruby")
		itemsTab.items[8] = item("Passive Jewel", "Jewel", "Ruby")

		itemsTab.slots["Weapon 1"] = slot("Weapon 1", 1, true)
		itemsTab.slots["Weapon 1 Swap"] = slot("Weapon 1 Swap", 2, false)
		itemsTab.slots["Body Armour"] = slot("Body Armour", 3, true)
		itemsTab.slots["Charm 1"] = slot("Charm 1", 4, true)
		itemsTab.slots["Flask 1"] = slot("Flask 1", 5, true)
		itemsTab.slots["Weapon 2"] = slot("Weapon 2", 6, true)
		itemsTab.slots["Gloves"] = slot("Gloves", 0, true)

		local jewelSlot = slot("Body Armour Jewel Socket 1", 7, true)
		jewelSlot.label = "Jewel #1"
		jewelSlot.parentSlot = itemsTab.slots["Body Armour"]
		itemsTab.orderedSlots = { itemsTab.slots["Body Armour"], jewelSlot }

		local passiveSocket = slot("Jewel 100", 8, true)
		passiveSocket.label = "Socket #1"
		passiveSocket.nodeId = 100
		itemsTab.sockets[100] = passiveSocket

		local rows = tradeQuery:BuildUpgradeRecommendationSlotRows()
		local labels = { }
		for _, row in ipairs(rows) do
			labels[row.label] = true
		end

		assert.is_true(labels["Weapon 1"])
		assert.is_true(labels["Body Armour"])
		assert.is_true(labels["Jewel #1"])
		assert.is_true(labels["Socket #1"])
		assert.is_nil(labels["Weapon 1 Swap"])
		assert.is_nil(labels["Charm 1"])
		assert.is_nil(labels["Flask 1"])
		assert.is_nil(labels["Weapon 2"])
		assert.is_nil(labels["Gloves"])
	end)

	it("scores candidates against the current baseline and filters non-upgrades", function()
		local row = {
			label = "Body Armour",
			slotName = "Body Armour",
			slot = slot("Body Armour", 1, true),
			slotTbl = { slotName = "Body Armour" },
		}
		local baseOutput = { TotalDPS = 100 }
		local calcFunc = function(context)
			local raw = context.repItem.raw or context.repItem:BuildRaw()
			if raw:find("Better Robe") then
				return { TotalDPS = 120 }
			end
			return { TotalDPS = 100 }
		end
		local best = tradeQuery:GetBestUpgradeRecommendationForSlot(row, {
			{ item_string = "Rarity: RARE\nSame Robe\nElementalist Robe" },
			{ item_string = "Rarity: RARE\nBetter Robe\nElementalist Robe" },
		}, calcFunc, baseOutput, tradeQuery.statSortSelectionList)

		assert.is_not_nil(best)
		assert.is_true(best.gain > 0.19)
		assert.is_nil(tradeQuery:GetBestUpgradeRecommendationForSlot(row, {
			{ item_string = "Rarity: RARE\nSame Robe\nElementalist Robe" },
		}, calcFunc, baseOutput, tradeQuery.statSortSelectionList))
	end)

	it("sorts recommendations by gain with slot label fallback", function()
		local sorted = tradeQuery:SortUpgradeRecommendations({
			{ gain = 1, row = { label = "Belt" } },
			{ gain = 2, row = { label = "Amulet" } },
			{ gain = 1, row = { label = "Boots" } },
		})

		assert.are.equals("Amulet", sorted[1].row.label)
		assert.are.equals("Belt", sorted[2].row.label)
		assert.are.equals("Boots", sorted[3].row.label)
	end)

	it("skips invalid fetched items during sanitization", function()
		local safe = tradeQuery:SanitizeFetchedItemsForRecommendation({
			{ id = "bad", item_string = "Rarity: RARE\nNot Real\nDefinitely Not A Base" },
			{ id = "good", item_string = "Rarity: RARE\nValid Robe\nElementalist Robe" },
		}, { slotName = "Body Armour" })

		assert.are.equals(1, #safe)
		assert.are.equals("good", safe[1].id)
	end)
end)
