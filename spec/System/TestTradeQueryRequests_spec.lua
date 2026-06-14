describe("TradeQueryRequests", function()
	local mock_limiter = {
		NextRequestTime = function()
			return os.time()
		end,
		InsertRequest = function()
			return 1
		end,
		FinishRequest = function() end,
		UpdateFromHeader = function() end,
		GetPolicyName = function(self, key)
			return key
		end
	}
	local requests = new("TradeQueryRequests", mock_limiter)

	describe("ProcessQueue", function()
		-- Pass: No changes to empty queues
		-- Fail: Alters queues unexpectedly, indicating loop errors, causing phantom requests
		it("skips empty queue", function()
			requests.requestQueue = { search = {}, fetch = {} }
			requests:ProcessQueue()
			assert.are.equal(#requests.requestQueue.search, 0)
		end)

		-- Pass: Dequeues and processes valid item
		-- Fail: Queue unchanged, indicating timing/insertion bug, blocking trade searches
		it("processes search queue item", function()
			local env = getfenv(requests.ProcessQueue)
			local orig_launch = env.launch
			env.launch = {
				DownloadPage = function(self, url, onComplete, opts)
					onComplete({ body = "{}", header = "HTTP/1.1 200 OK" }, nil)
				end
			}
			table.insert(requests.requestQueue.search, {
				url = "test",
				callback = function() end,
				retryTime = nil
			})
			local function mock_next_time(self, policy, time)
				return time - 1
			end
			mock_limiter.NextRequestTime = mock_next_time
			requests:ProcessQueue()
			assert.are.equal(#requests.requestQueue.search, 0)
			env.launch = orig_launch
		end)

		-- Pass: Search queue waits 5 seconds between dispatches and reports the wait
		-- Fail: Immediate second search risks repeated rate limiting during recommendations
		it("spaces search requests by 5 seconds", function()
			local orig_os_time = os.time
			local requests = new("TradeQueryRequests", mock_limiter)
			local env = getfenv(requests.ProcessQueue)
			local orig_launch = env.launch
			local mock_time = 1000
			local downloadCount = 0
			os.time = function() return mock_time end
			env.launch = {
				DownloadPage = function(self, url, onComplete, opts)
					downloadCount = downloadCount + 1
					onComplete({ body = "{}", header = "HTTP/1.1 200 OK" }, nil)
				end
			}
			mock_limiter.NextRequestTime = function(self, policy, time)
				return time - 1
			end
			table.insert(requests.requestQueue.search, {
				url = "first",
				callback = function() end,
			})
			table.insert(requests.requestQueue.search, {
				url = "second",
				callback = function() end,
			})

			requests:ProcessQueue()
			assert.are.equal(1, downloadCount)
			assert.are.equal(1, #requests.requestQueue.search)

			local capturedBackoff = nil
			local capturedRateLimited = nil
			requests:ProcessQueue(function(backoff, rateLimited)
				capturedBackoff = backoff
				capturedRateLimited = rateLimited
			end)
			assert.are.equal(5, capturedBackoff)
			-- waiting purely on the 5s self-pacing is not a real rate limit
			assert.is_false(capturedRateLimited)
			assert.are.equal(1, downloadCount)
			assert.are.equal(1, #requests.requestQueue.search)

			mock_time = mock_time + 5
			requests:ProcessQueue()
			assert.are.equal(2, downloadCount)
			assert.are.equal(0, #requests.requestQueue.search)

			os.time = orig_os_time
			env.launch = orig_launch
		end)

		-- Pass: Does not crash on 401, and passes error message
		-- Fail: Crash, or returned error is wrong
		it("does not crash on 401", function()
			local json = '"{"error":"invalid_token","error_description":"The access token provided is invalid or has expired"}"'
			local header = [[HTTP/1.1 401 Unauthorized
Date: Fri, 24 Apr 2026 07:30:38 GMT
Content-Type: application/json
Transfer-Encoding: chunked
Connection: keep-alive
Server: cloudflare
WWW-Authenticate: Bearer realm="pathofexile:production", error="invalid_token", error_description="The access token provided is invalid or has expired"
Cache-Control: no-store
Strict-Transport-Security: max-age=63115200; includeSubDomains; preload]]
			local env = getfenv(requests.ProcessQueue)
			local orig_launch = env.launch
			local orig_reset_details = env.main.api.ResetDetails
			env.main.api.ResetDetails = function() end
			env.launch = {
				DownloadPage = function(self, url, onComplete, opts)
					onComplete({ body = json, header = header }, "Response code: 401")
				end
			}
			requests.requestQueue = { search = {}, fetch = {} }
			requests.nextSearchTime = 0
			table.insert(requests.requestQueue.search, {
				url = "test",
				callback = function(body, msg)
					assert.are.equal(body, json)
					assert.truthy(msg:find("Response code: 401"))
				end,
				retryTime = nil
			})
			local function mock_next_time(self, policy, time)
				return time - 1
			end
			mock_limiter.NextRequestTime = mock_next_time
			requests:ProcessQueue()
			assert.are.equal(0, #requests.requestQueue.search)
			env.launch = orig_launch
			env.main.api.ResetDetails = orig_reset_details
		end)

		-- Pass: Retries every 5 seconds after 429, preventing aggressive repeat searches
		-- Fail: Lower backoff indicates retry bug, risking repeated API rate limits
		it("retries on 429 with fixed 5 second backoff", function()
			local orig_os_time = os.time
			local requests = new("TradeQueryRequests", mock_limiter)
			local env = getfenv(requests.ProcessQueue)
			local orig_launch = env.launch
			local mock_time = 1000
			local downloadCalled = false
			os.time = function() return mock_time end
			env.launch = {
				DownloadPage = function(self, url, onComplete, opts)
					downloadCalled = true
					onComplete({ body = "", header = "HTTP/1.1 429 Too Many Requests\nRetry-After: 3" }, nil)
				end
			}

			local request = {
				url = "test",
				callback = function() end,
				retryTime = nil,
				attempts = 0
			}
			requests.requestQueue = { search = {}, fetch = {} }
			table.insert(requests.requestQueue.search, request)

			mock_limiter.NextRequestTime = function(self, policy, time)
				return time - 1
			end
			assert.are.equal(mock_time - 1, requests.rateLimiter:NextRequestTime("search", mock_time))
			assert.are.equal(1, #requests.requestQueue.search)

			for i = 1, 7 do
				local previous_time = mock_time
				local capturedBackoff = nil
				local capturedRateLimited = nil
				downloadCalled = false
				requests:ProcessQueue(function(backoff, rateLimited)
					capturedBackoff = backoff
					capturedRateLimited = rateLimited
				end)
				assert.is_true(downloadCalled)
				-- a 429 response is a genuine rate limit
				assert.is_true(capturedRateLimited)
				assert.are.equal(1, #requests.requestQueue.search)
				assert.are.equal(i, requests.requestQueue.search[1].attempts)
				local expected_backoff = 5
				assert.are.equal(expected_backoff, capturedBackoff)
				assert.are.equal(previous_time + expected_backoff, requests.requestQueue.search[1].retryTime)
				mock_time = requests.requestQueue.search[1].retryTime
			end

			-- Validate skip when time < retryTime
			mock_time = requests.requestQueue.search[1].retryTime - 1
			local function mock_next_time(self, policy, time)
				return time - 1
			end
			mock_limiter.NextRequestTime = mock_next_time
			requests:ProcessQueue()
			assert.are.equal(1, #requests.requestQueue.search)

			os.time = orig_os_time
			env.launch = orig_launch
		end)
	end)

	describe("SearchWithQueryWeightAdjusted", function()
		-- Pass: Caps at 5 calls on large results
		-- Fail: Exceeds 5, indicating loop without bound, risking stack overflow or endless API calls
		it("respects recursion limit", function()
			local call_count = 0
			local orig_perform = requests.PerformSearch
			local orig_fetchBlock = requests.FetchResultBlock
			local valid_query = [[{"query":{"stats":[{"value":{"min":0}}]}}]]
			local test_ids = {}
			for i = 1, 11 do
				table.insert(test_ids, "item" .. i)
			end
			requests.PerformSearch = function(self, realm, league, query, callback)
				call_count = call_count + 1
				local response
				if call_count >= 5 then
					response = { total = 11, result = test_ids, id = "id" }
				else
					response = { total = 10000, result = { "item1" }, id = "id" }
				end
				callback(response, nil)
			end
			requests.FetchResultBlock = function(self, url, callback)
				local param_item_hashes = url:match("fetch/([^?]+)")
				local hashes = {}
				if param_item_hashes then
					for hash in param_item_hashes:gmatch("[^,]+") do
						table.insert(hashes, hash)
					end
				end
				local processedItems = {}
				for _, hash in ipairs(hashes) do
					table.insert(processedItems, {
						amount = 1,
						currency = "chaos",
						item_string = "Test Item",
						whisper = "hi",
						weight = "100",
						id = hash
					})
				end
				callback(processedItems)
			end
			requests:SearchWithQueryWeightAdjusted("pc", "league", valid_query, function(items)
				assert.are.equal(call_count, 5)
			end, {})
			requests.PerformSearch = orig_perform
			requests.FetchResultBlock = orig_fetchBlock
		end)
	end)

	describe("FetchResults", function()
		-- Pass: Fetches exactly 10 from 11, in 1 block
		-- Fail: Fetches wrong count/blocks, indicating batch limit violation, triggering rate limits
		it("fetches up to maxFetchPerSearch items", function()
			local itemHashes = { "id1", "id2", "id3", "id4", "id5", "id6", "id7", "id8", "id9", "id10", "id11" }
			local block_count = 0
			local orig_fetchBlock = requests.FetchResultBlock
			requests.FetchResultBlock = function(self, url, callback)
				block_count = block_count + 1
				local param_item_hashes = url:match("fetch/([^?]+)")
				local hashes = {}
				if param_item_hashes then
					for hash in param_item_hashes:gmatch("[^,]+") do
						table.insert(hashes, hash)
					end
				end
				local processedItems = {}
				for _, hash in ipairs(hashes) do
					table.insert(processedItems, {
						amount = 1,
						currency = "chaos",
						item_string = "Test Item",
						whisper = "hi",
						weight = "100",
						id = hash
					})
				end
				callback(processedItems)
			end
			requests:FetchResults(itemHashes, "queryId", function(items)
				assert.are.equal(#items, 10)
				assert.are.equal(block_count, 1)
			end)
			requests.FetchResultBlock = orig_fetchBlock
		end)
	end)
end)
