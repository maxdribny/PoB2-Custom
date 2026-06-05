-- Path of Building
--
-- Module: Logger
-- Handles logging to both console and file
--

local Logger = {}

function Logger:Init(repoRoot)
	self.repoRoot = repoRoot or "."
	-- Keep logs in repo-root /logs/
	self.logsDir = self.repoRoot .. "/logs"
	self.logFile = nil
	self.originalConPrintf = ConPrintf
	self.loggingEnabled = false
	self._buffer = {}
	self._bufferMaxLines = 5000
	self._startupBuffering = true
	self._startupMarks = {}
	self._lastFlushTime = GetTime and GetTime() or 0

	-- Try to create logs directory
	self:EnsureLogsDir()

	-- Try to open log file with timestamp
	local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
	self.logFilePath = self.logsDir .. "/pob_" .. timestamp .. ".log"

	-- Attempt to open the file; gracefully degrade if it fails
	local success, err = pcall(function()
		self.logFile = io.open(self.logFilePath, "w")
	end)

	if success and self.logFile then
		self.loggingEnabled = true
		self:Write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] Logger initialized")
		self:Write("Log file: " .. self.logFilePath)
		self.originalConPrintf("Logger: File logging enabled at " .. self.logFilePath)
	else
		self.originalConPrintf("Logger: Could not open log file, console-only mode")
		self.logFile = nil
	end

	-- Override global ConPrintf to also write to file.
	-- Guard against % in messages by never passing fmt as a raw format string.
	local logger = self
	ConPrintf = function(fmt, ...)
		local msg
		if select('#', ...) > 0 then
			msg = string.format(tostring(fmt), ...)
		else
			msg = tostring(fmt)
		end
		logger:OriginalConPrintf(msg)
		if logger.loggingEnabled then
			logger:Write("[" .. os.date("%H:%M:%S") .. "] " .. msg)
		end
	end
end

function Logger:EnsureLogsDir()
	-- Prefer host-provided MakeDir (no shell spawn), fall back gracefully.
	if MakeDir then
		local ok = MakeDir(self.logsDir)
		return ok ~= nil and ok ~= false
	end
	return false
end

function Logger:OriginalConPrintf(msg)
	-- Call the original ConPrintf from SimpleGraphic using %s to avoid format-string crashes.
	if self.originalConPrintf then
		self.originalConPrintf("%s", msg)
	end
end

function Logger:Write(msg)
	if not self.logFile then
		return
	end
	-- Buffer writes to avoid per-line flush overhead (especially during startup)
	table.insert(self._buffer, msg)
	if #self._buffer > self._bufferMaxLines then
		-- Drop oldest lines rather than growing unbounded
		table.remove(self._buffer, 1)
	end
	if not self._startupBuffering then
		local now = GetTime and GetTime() or 0
		if #self._buffer >= 100 or (now - (self._lastFlushTime or 0)) >= 1000 then
			self:Flush()
		end
	end
end

function Logger:Flush()
	if not self.logFile or #self._buffer == 0 then
		return
	end
	for i = 1, #self._buffer do
		self.logFile:write(self._buffer[i] .. "\n")
	end
	self._buffer = {}
	self.logFile:flush()
	self._lastFlushTime = GetTime and GetTime() or 0
end

function Logger:Mark(label)
	if not (GetTime and label) then
		return
	end
	table.insert(self._startupMarks, { label = tostring(label), t = GetTime() })
end

function Logger:ImportMarks(marks)
	if type(marks) ~= "table" then
		return
	end
	for i = 1, #marks do
		local m = marks[i]
		if type(m) == "table" and m.label and m.t then
			table.insert(self._startupMarks, { label = tostring(m.label), t = m.t })
		end
	end
end

function Logger:EmitStartupTimings()
	if not self.loggingEnabled or #self._startupMarks == 0 then
		self._startupBuffering = false
		return
	end
	table.sort(self._startupMarks, function(a, b) return a.t < b.t end)
	local t0 = self._startupMarks[1].t
	self:Write("[" .. os.date("%H:%M:%S") .. "] Startup timings (ms):")
	local last = t0
	for i = 1, #self._startupMarks do
		local m = self._startupMarks[i]
		local dt = m.t - t0
		local step = m.t - last
		self:Write(string.format("  +%4d  (Δ%4d)  %s", dt, step, m.label))
		last = m.t
	end
	self._startupBuffering = false
	self:Flush()
end

function Logger:Close()
	if self.logFile then
		self:Write("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] Logger closed")
		self:Flush()
		self.logFile:close()
		self.logFile = nil
	end
end

return Logger
