local speaker = peripheral.find("speaker")
if (not speaker) then error("error: speaker not found") end

local success, httpPlayer = pcall(require, "httpPlayer")
if (not success) then
    shell.run("wget https://github.com/noodle2521/computercraft/raw/main/httpPlayer.lua httpPlayer.lua")
    httpPlayer = require("httpPlayer")
end


local songListPath = "caches/song_list.txt"
local playlistsPath = "caches/playlists.txt"


-- cache tables
local songList = {}
local playlists = {}

local sortedPlaylists = {}

-- constants
local bytesPerSecond = 6000 -- 48kHz cc: tweaked speakers, dfpwm has 1 bit samples
local screenWidth = term.getSize()

--- ui variables
local uiLayer = 1
local pageOffset = 0
--current playlist
local currentPlaylist


local function updateCache(cacheTable, path)
	local cacheFile = fs.open(path, "w")

    for _, line in ipairs(cacheTable) do
        cacheFile.writeLine(table.concat(line, "|"))
    end

	cacheFile.close()
end

local function readCache(cacheTable, path)
    if (fs.exists(path)) then
        local file = fs.open(path, "r")
        local line = file.readLine()
        local i = 1
        while (line) do
            local entry = {}
            for str in string.gmatch(line, "[^%|]+") do
                table.insert(entry, str)
            end
            cacheTable[i] = entry
            
            line = file.readLine()
            i = i + 1
        end
    end
end

local function updatePlaylists(removedIndex)
    for i, line in ipairs(playlists) do
        local songInPlaylist = false

        -- binary search sorted playlist
        local sorted = sortedPlaylists[i]
        local k , j = 1, #sorted
        while (j > k) do
            if (sorted[k] == removedIndex or sorted[j] == removedIndex) then
                songInPlaylist = true
                break
            end

            local mid = math.floor(k + (j/2))
            if (removedIndex < mid) then
                j = mid - 1
            elseif (removedIndex > mid) then
                k = mid + 1
            else
                songInPlaylist = true
                break
            end
        end

        if (songInPlaylist) then
            local songs = { table.unpack(line, 2) }
            for i, song in ipairs(songs) do
                local id = tonumber(song)
                if (id > removedIndex) then
                    line[i] = id - 1;
                end
            end
        end
    end
end

-- *** INCONSISTENT DEPENDING ON VERSION OF CC: TWEAKED
local function keyToDigit(key)
    if (key < keys.zero or key > keys.nine) then
        --error("key is not a digit")
        return -1
    end

    return key - keys.one + 1
end


--- ui functions
local function playSongWithUI(url, prevName, nextName, doAutoExit)
    doAutoExit = doAutoExit or true

    local allowSeek, audioByteLength = httpPlayer.pollUrl(url)
    if (allowSeek == nil) then
        return
    end

    local songLength = math.floor(audioByteLength / bytesPerSecond)

    local exit = false
    local paused = false
    local playbackOffset = 0
    local lastChunkByteOffset = 0
    --local lastChunkTime = os.clock()

    local function playSong()
        if (not paused) then
            local interrupt = httpPlayer.playFromUrl(url, "song_interrupt", "chunk_queued", playbackOffset, allowSeek, audioByteLength)
            if (not interrupt) then
                if (doAutoExit) then
                    exit = true
                else
                    paused = true
                    playbackOffset = 0
                end
            end
        else
            os.pullEvent("song_interrupt")
        end
    end
    
    local function updateLastChunk()
        while true do
            _, lastChunkByteOffset, _ = os.pullEvent("chunk_queued")
            lastChunkByteOffset = math.max(lastChunkByteOffset - httpPlayer.chunkSize, 0) -- awful nightmare duct tape solution to fix pausing but it is what it is
        end
    end

    local function seek(newOffset)
        if (allowSeek) then
            os.queueEvent("song_interrupt")

            local clampedOffset = math.max(0, math.min(newOffset, audioByteLength - 1))
            playbackOffset = clampedOffset

            lastChunkByteOffset = clampedOffset
            --lastChunkTime = os.clock()
        end
    end

    local function songUI()
        local key, keyPressed
        local timer = os.startTimer(1)

        local function pullKeyEvent()
            local _
            _, key = os.pullEvent("key_up")
            keyPressed = true
        end
        local function secondTimer()
            local _, id
            repeat
                _, id = os.pullEvent("timer")
            until (id == timer)

            timer = os.startTimer(1)
        end


        while true do
            repeat
                parallel.waitForAny(pullKeyEvent, secondTimer)
                term.clear()
                --print(lastChunkByteOffset)

                -- scrubber bar
                local songPos = math.floor((screenWidth - 2 - 1) * (lastChunkByteOffset / audioByteLength))
                print("|" .. string.rep("-", songPos) .. "o" .. string.rep("-", screenWidth - 2 - songPos - 1) .. "|")
                -- song time display
                local songTime = math.floor(lastChunkByteOffset / bytesPerSecond)
                print(string.format("%02d:%02d / %02d:%02d", math.floor(songTime / 60), math.floor(math.fmod(songTime, 60)), math.floor(songLength / 60), math.floor(math.fmod(songLength, 60))))

                print("\n\nspace: pause, 0-9: seek, A,D: back/forward 10s, J,K: prev/next song, X: exit")
            until keyPressed
            keyPressed = false


            local digit = keyToDigit(key)
            if (digit >= 0) then
                local newOffset = math.floor((digit / 10) * audioByteLength)
                seek(newOffset)
            end
            if (key == keys.space) then
                paused = not paused
                if (paused) then
                    seek(lastChunkByteOffset)
                else
                    os.queueEvent("song_interrupt")
                end
            end
            if (key == keys.a) then
                -- estimate offset of current playback
                --local currentOffset = lastChunkByteOffset + (6000 * (math.floor(os.clock()) - lastChunkTime))

                local newOffset = lastChunkByteOffset - (10 * 6000)
                seek(newOffset)
            end
            if (key == keys.d) then
                -- estimate offset of current playback
                --local currentOffset = lastChunkByteOffset + (6000 * (math.floor(os.clock()) - lastChunkTime))

                local newOffset = lastChunkByteOffset + (10 * 6000)
                seek(newOffset)
            end
            if (key == keys.j) then
                
            end
            if (key == keys.k) then
                
            end
            if (key == keys.x) then
                os.queueEvent("song_interrupt")
                exit = true
            end
        end
    end


    repeat
        parallel.waitForAny(playSong, songUI, updateLastChunk)
    until exit
    os.sleep(0.5)
end

local function songListUI()
    local currentSongs = songList
    local playlistName = "songs"
    if (currentPlaylist > 0) then
        local currentSongIDs = { table.unpack(playlists[currentPlaylist], 2) }
        currentSongs = {}
        for i, id in currentSongIDs do
            table.insert(currentSongs, songList[id])
        end
        playlistName = playlists[currentPlaylist][1]
    end
    local maxSongPage = math.ceil(#currentSongs / 10) - 1

    print(playlistName .. ":\n")
    if (#currentSongs == 0) then
        print("none")
    else
        local start = (pageOffset) * 10 + 1
        for i = start, start + 9 do
            if (not currentSongs[i]) then
                break
            end

            print(i .. ". " .. currentSongs[i][1])
        end
    end

    print("\n\n1-0: play song, J,K: page down/up, A: add song, E: edit song, D: delete song, P: add to playlist, tab: playlists menu, X: exit")

    local event, key = os.pullEvent("key_up")
    local digit = keyToDigit(key)
    if (digit == 0) then
        digit = 10
    end
    if (digit >= 0 and #currentSongs ~= 0) then
        local num = digit + (pageOffset * 10)

        if (currentSongs[num]) then
            playSongWithUI(currentSongs[num][2])
        end
    end
    -- jrop and klimb :relieved:
    if (key == keys.j) then
        pageOffset = math.min(pageOffset + 1, maxSongPage)
    end
    if (key == keys.k) then
        pageOffset = math.max(pageOffset - 1, 0)
    end
    if (key == keys.a) then
        term.clear()

        print("new song title (spaces fine, pls no | thats my string separator):")
        local input1 = read()
        if (input1 == "") then
            return
        end
        while (string.find(input1, "%|")) do
            print(">:(")
            input1 = read()
        end
        --songList[#songList+1][1] = input

        print("new song url (pls no | here either):")
        local input2 = read()
        if (input2 == "") then
            return
        end
        while (string.find(input2, "%|")) do
            print(">:(")
            input2 = read()
        end
        --songList[#songList+1][2] = input

        table.insert(songList, {input1, input2})
        table.insert(playlists[currentPlaylist], #songList)

        updateCache(songList, songListPath)
        updateCache(playlists, playlistsPath)
    end
    if (key == keys.e) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #currentSongs > 0) then
            local num = _digit + (pageOffset * 10)

            if (currentSongs[num]) then
                term.clear()

                print("new song title (spaces fine, pls no | thats my string separator):")
                local song = songList[playlists[currentPlaylist][num + 1]]
                local input1
                repeat
                    input1 = read()
                    if (input1 == "") then input1 = song[1] end
                until not string.find(input1, "%|")

                print("new song url (pls no | here either):")
                local input2
                repeat
                    input2 = read()
                    if (input2 == "") then input2 = song[2] end
                until not string.find(input2, "%|")
                
                songList[playlists[currentPlaylist][num + 1]] = {input1, input2}

                updateCache(songList, songListPath)
            end
        end
    end
    if (key == keys.d) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #currentSongs > 0) then
            local num = _digit + (pageOffset * 10)

            if (currentSongs[num]) then
                print("removing " .. currentSongs[num][1])
                table.remove(songList, playlists[currentPlaylist][num + 1])
                updateCache(songList, songListPath)
                updatePlaylists(playlists[currentPlaylist][num + 1])
                os.sleep(1)
            end
        end
    end
    if (key == keys.p) then
        if (#playlists == 0) then
            print("no playlists found")
            return
        end

        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #currentSongs > 0) then
            local num = _digit + (pageOffset * 10)

            if (currentSongs[num]) then
                term.clear()

                local input
                repeat
                    print("to which playlist? (1-" .. #playlists .. ")")
                    input = tonumber(read())
                until playlists[input + 1]

                table.insert(playlists[input + 1], playlists[currentPlaylist][num])
                updateCache(playlists, playlistsPath)
            end
        end
    end
    if (key == keys.tab) then
        uiLayer = 2
    end
    if (key == keys.x) then
        uiLayer = 0
    end
end

local function playlistsUI()
    --
end


---- main
-- read from song_list.txt if exists
readCache(songList, songListPath)

-- read from playlists.txt if exists
readCache(playlists, playlistsPath)

-- if playlists empty, build global playlist as first entry
if (#playlists == 0) then
    playlists[1] = {""}
    for i=1, #songList do
        table.insert(playlists[1], i)
    end
end

-- generate sortedPlaylists for faster contains check
for i, line in ipairs(playlists) do
    local sortedLine = { table.unpack(line, 2) }
    table.sort(sortedLine)
    sortedPlaylists[i] = sortedLine
end

-- initialize with global playlist open
currentPlaylist = 1


--- ui loop
while true do
    term.clear()

    if (uiLayer == 1) then
        songListUI()
    elseif (uiLayer == 2) then
        playlistsUI()
    else
        break
    end
end