local dkjson = require "dkjson"

describe("Trade search URL building #trade", function()
	local tq

	before_each(function()
		tq = new("TradeQuery", { })
		tq.pbRealm = "poe2"
		tq.pbLeague = "Runes of Aldur"
	end)

	-- A weighted slot query like the ones stored in self.lastQueries
	local function sampleQuery()
		return [[{"query":{"status":{"option":"securable"},"stats":[{"type":"weight","filters":[{"id":"explicit.stat_123","value":{"weight":2.0}}],"value":{"min":100,"max":200}}]},"sort":{"statgroup.0":"desc"}}]]
	end

	it("builds a fragment-free short search URL from a query id", function()
		local url = tq.tradeQueryRequests:buildUrl(tq.hostName .. "trade2/search", tq.pbRealm, tq.pbLeague, "abc123")
		-- a logged-out browser forwards this as the OAuth redirect_uri, so it must
		-- contain neither a literal '#' nor an encoded one
		assert.is_nil(url:find("#", 1, true))
		assert.is_nil(url:find("%%23"))
		assert.is_not_nil(url:find("/abc123$"))
	end)

	it("omits the account filter so prefill URLs stay fragment-free", function()
		local query = tq:BuildWeightBandQuery(sampleQuery(), 150.4, nil)
		assert.is_nil(query:find("account", 1, true))

		local url = tq:BuildPrefillSearchUrl(query)
		assert.is_nil(url:find("#", 1, true))
		assert.is_nil(url:find("%%23"))
	end)

	it("keeps the account filter inside the query body for API searches", function()
		local query = tq:BuildWeightBandQuery(sampleQuery(), 150.4, "pandadarren#0763")
		local decoded = dkjson.decode(query)
		assert.are.equals("pandadarren#0763", decoded.query.filters.trade_filters.filters.account.input)
		-- the raw '#' lives in the JSON body; this is exactly why this string must
		-- never be placed into a prefill (?q=) URL
		assert.is_not_nil(query:find("pandadarren#0763", 1, true))
	end)

	it("pins the trade-sum weight to a +/-1 band", function()
		local decoded = dkjson.decode(tq:BuildWeightBandQuery(sampleQuery(), 172.0, nil))
		assert.are.equals(171, decoded.query.stats[1].value.min)
		assert.are.equals(173, decoded.query.stats[1].value.max)
	end)
end)
