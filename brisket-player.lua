local speaker = peripheral.find("speaker")
if (not speaker) then error("error: speaker not found") end

local success, urlPlayer = pcall(require, "url-player")
if (not success) then
    shell.run("wget https://raw.githubusercontent.com/mushcalli/brisket-player/refs/heads/main/url-player.lua url-player.lua")
    urlPlayer = require("url-player")
end


local songListPath = "caches/song_list.txt"
local playlistsPath = "caches/playlists.txt"


-- cache tables
local songList = {}
local playlists = {}

-- constants
local bytesPerSecond = 6000 -- 48kHz cc: tweaked speakers, dfpwm has 1 bit samples
local screenWidth = term.getSize()

--- ui variables
local uiLayer = 1
local songPageOffset = 0
local playlistPageOffset = 0
local songQueue = {}
local queuePos = 1
local shuffle = false
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

local function updatePlaylistsOnSongDelete(removedSongIndex)
    removedSongIndex = tonumber(removedSongIndex)

    for _, line in ipairs(playlists) do
        local songs = { table.unpack(line, 2) }
        for i, song in ipairs(songs) do
            local id = tonumber(song)
            if (id == removedSongIndex) then
                table.remove(line, i + 1)
            end
            if (id > removedSongIndex) then
                line[i + 1] = id - 1;
            end
        end
    end

    updateCache(playlists, playlistsPath)
end

local function updatePlaylistsOnNewSong()
    table.insert(playlists[1], #songList) -- add latest song to global playlist

    updateCache(playlists, playlistsPath)
end

local function removeFromPlaylist(removedSongIndex, playlistIndex)
    removedSongIndex = tonumber(removedSongIndex)
    playlistIndex = tonumber(playlistIndex)

    -- original playlist isnt sorted and might have duplicates of songs, just linear search ig
    for i = 2, #playlists[playlistIndex] do
        if (tonumber(playlists[playlistIndex][i]) == removedSongIndex) then
            table.remove(playlists[playlistIndex], i)
        end
    end

    updateCache(playlists, playlistsPath)
end

-- generates new song queue from current playlist
local function refreshSongQueue()
    local currentSongIndexes = { table.unpack(playlists[currentPlaylist], 2) }
    songQueue = {}
    for i, id in ipairs(currentSongIndexes) do
        local song = {}
        table.move(songList[tonumber(id)], 1, 2, 1, song)
        table.insert(song, i) -- append song's original queue position to restore upon unshuffling
        table.insert(songQueue, song)
    end
end

-- *** WHETHER 0 IS LOWEST OR HIGHEST IN THE KEYS TABLE IS INCONSISTENT DEPENDING ON VERSION OF CC: TWEAKED
local function keyToDigit(key)
    if (keys.zero < keys.nine) then
        -- use zero-lowest ordering

        if (key < keys.zero or key > keys.nine) then
            --error("key is not a digit")
            return -1
        end

        return key - keys.zero
    else
        -- use zero-last ordering
        if (key < keys.one or key > keys.zero) then
            --error("key is not a digit")
            return -1
        end

        local num = key - keys.one + 1
        if (num == 10) then num = 0 end
        return num
    end
end


--- ui functions
local function songListUI()
    -- populate songQueue from current playlist
    refreshSongQueue()

    shuffle = false

    local playlistName = playlists[currentPlaylist][1]
    local maxSongPage = math.ceil(#songQueue / 10) - 1

    print(playlistName .. ":\n")
    if (#songQueue == 0) then
        print("none")
    else
        local start = (songPageOffset) * 10 + 1
        for i = start, start + 9 do
            if (not songQueue[i]) then
                break
            end

            print(i .. ". " .. songQueue[i][1])
        end
    end

    print("\n\n1-0: play, J,K: ^/v, N: new, E: edit, D: del, A,R: add/remove from playlist, tab: playlists, X: exit")

    local event, key = os.pullEvent("key_up")

    local digit = keyToDigit(key)
    if (digit == 0) then
        digit = 10
    end
    if (digit > 0 and #songQueue ~= 0) then
        local num = digit + (songPageOffset * 10)

        if (songQueue[num]) then
            -- enter songPlayerUI
            uiLayer = 3
            queuePos = num
        end
    end

    -- jrop and klimb :relieved:
    if (key == keys.j) then
        songPageOffset = math.min(songPageOffset + 1, maxSongPage)
    end
    if (key == keys.k) then
        songPageOffset = math.max(songPageOffset - 1, 0)
    end
    if (key == keys.n) then
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
        if (currentPlaylist > 1) then
            table.insert(playlists[currentPlaylist], #songList)
        end

        updateCache(songList, songListPath)
        updatePlaylistsOnNewSong()
        --updateCache(playlists, playlistsPath)
    end
    if (key == keys.e) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit > 0 and #songQueue > 0) then
            local num = _digit + (songPageOffset * 10)

            if (songQueue[num]) then
                term.clear()

                print("new song title (spaces fine, pls no | thats my string separator):")
                local song = songList[tonumber(playlists[currentPlaylist][num + 1])]
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
                
                songList[tonumber(playlists[currentPlaylist][num + 1])] = {input1, input2}

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
        if (_digit > 0 and #songQueue > 0) then
            local num = _digit + (songPageOffset * 10)

            if (songQueue[num]) then
                print("removing " .. songQueue[num][1])
                table.remove(songList, tonumber(playlists[currentPlaylist][num + 1]))
                updateCache(songList, songListPath)
                updatePlaylistsOnSongDelete(playlists[currentPlaylist][num + 1])
                --updateCache(playlists, playlistsPath)
                os.sleep(1)
            end
        end
    end
    if (key == keys.a) then
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
        if (_digit > 0 and #songQueue > 0) then
            local num = _digit + (songPageOffset * 10)

            if (songQueue[num]) then
                term.clear()

                local input
                repeat
                    print("to which playlist? (1-" .. #playlists - 1 .. ")")
                    input = read()
                    if (input == "") then
                        return
                    end
                    input = tonumber(input)
                until input and playlists[input + 1]

                table.insert(playlists[input + 1], tonumber(playlists[currentPlaylist][num + 1]))
                updateCache(playlists, playlistsPath)
            end
        end
    end
    if (key == keys.r) then
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
        if (_digit > 0 and #songQueue > 0) then
            local num = _digit + (songPageOffset * 10)

            if (songQueue[num]) then
                term.clear()

                local input
                repeat
                    print("from which playlist? (1-" .. #playlists - 1 .. ")")
                    input = read()
                    if (input == "") then
                        return
                    end
                    input = tonumber(input)
                until input and playlists[input + 1]

                removeFromPlaylist(playlists[currentPlaylist][num + 1], currentPlaylist)
                --updateCache(playlists, playlistsPath)
            end
        end
    end
    if (key == keys.tab) then
        -- enter playlistsUI
        uiLayer = 2
    end
    if (key == keys.x) then
        uiLayer = 0
    end
end


local function playlistsUI()
    local maxPlaylistPage = math.ceil((#playlists - 1) / 10) - 1

    print("playlists:\n")

    if (#playlists <= 1) then
        print("none")
    else
        local start = (playlistPageOffset) * 10 + 2
        for i = start, start + 9 do
            if (not playlists[i]) then
                break
            end

            if (i == currentPlaylist) then
                print(">. " .. playlists[i][1])
            else
                print(i-1 .. ". " .. playlists[i][1])
            end
        end
    end

    print("\n\n1-0: select playlist, backspace: clear selection, J,K: page down/up, N: new playlist, E: rename playlist, D: delete playlist, tab: back to song list")

    local event, key = os.pullEvent("key_up")

    local digit = keyToDigit(key)
    if (digit == 0) then
        digit = 10
    end
    if (digit > 0 and #playlists > 1) then
        local num = digit + (playlistPageOffset * 10) + 1

        if (currentPlaylist == num) then
            currentPlaylist = 1
            return
        end

        if (playlists[num]) then
            currentPlaylist = num
        end
    end

    if (key == keys.backspace) then
        currentPlaylist = 1
    end
    -- jrop and klimb yet again
    if (key == keys.j) then
        playlistPageOffset = math.min(playlistPageOffset + 1, maxPlaylistPage)
    end
    if (key == keys.k) then
        playlistPageOffset = math.max(playlistPageOffset - 1, 0)
    end
    if (key == keys.n) then
        term.clear()

        print("new playlist name (spaces fine, pls no | thats my string separator):")
        local input1 = read()
        if (input1 == "") then
            return
        end
        while (string.find(input1, "%|")) do
            print(">:(")
            input1 = read()
        end

        table.insert(playlists, {input1})

        updateCache(playlists, playlistsPath)
    end
    if (key == keys.e) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit > 0 and #playlists > 1) then
            local num = _digit + (playlistPageOffset * 10) + 1

            if (playlists[num]) then
                term.clear()

                print("new playlist name (spaces fine, pls no | thats my string separator):")
                local currentName = playlists[num][1]
                local input1
                repeat
                    input1 = read()
                    if (input1 == "") then input1 = currentName end
                until not string.find(input1, "%|")
                
                playlists[num][1] = input1

                updateCache(playlists, playlistsPath)
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
        if (_digit > 0 and #playlists > 0) then
            local num = _digit + (playlistPageOffset * 10) + 1

            if (playlists[num]) then
                print("removing " .. playlists[num][1])
                table.remove(playlists, num)
                updateCache(playlists, playlistsPath)

                if (currentPlaylist == num) then
                    currentPlaylist = 1
                end

                os.sleep(1)
            end
        end
    end
    if (key == keys.tab or key == keys.x) then
        -- enter songListUI
        uiLayer = 1
    end
end


local function songPlayerUI()
    local title = songQueue[queuePos][1]
    local url = songQueue[queuePos][2]

    local supportsPartialRequests, audioByteLength = urlPlayer.pollUrl(url)
    if (supportsPartialRequests == nil) then
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
            local interrupt = urlPlayer.playFromUrl(url, "song_interrupt", "chunk_queued", playbackOffset, supportsPartialRequests, audioByteLength)
            if (not interrupt) then
                if (queuePos < #songQueue) then
                    queuePos = queuePos + 1
                else
                    queuePos = 1
                end
            end
        else
            os.pullEvent("song_interrupt")
        end
    end
    
    local function updateLastChunk()
        while true do
            _, lastChunkByteOffset, _ = os.pullEvent("chunk_queued")
            lastChunkByteOffset = math.max(lastChunkByteOffset - urlPlayer.chunkSize, 0) -- awful nightmare duct tape solution to fix pausing but it is what it is
        end
    end

    local function seek(newOffset)
        --if (supportsPartialRequests) then
            os.queueEvent("song_interrupt")

            local clampedOffset = math.max(0, math.min(newOffset, audioByteLength - 1))
            playbackOffset = clampedOffset

            lastChunkByteOffset = clampedOffset
            --lastChunkTime = os.clock()
        --end
    end

    local function songUI()
        exit = false

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
                term.clear()
                print(title)

                -- scrubber bar
                local songPos = math.floor((screenWidth - 2 - 1) * (lastChunkByteOffset / audioByteLength))
                print("\n|" .. string.rep("-", songPos) .. "o" .. string.rep("-", screenWidth - 2 - songPos - 1) .. "|")
                -- song time display
                local songTime = math.floor(lastChunkByteOffset / bytesPerSecond)
                print(string.format("%02d:%02d / %02d:%02d", math.floor(songTime / 60), math.floor(math.fmod(songTime, 60)), math.floor(songLength / 60), math.floor(math.fmod(songLength, 60))))
                
                -- DEBUG
                --print(lastChunkByteOffset)

                print("\nspace: pause, 0-9: seek, A,D: back/forward 10s, J,K: prev/next song, R: shuffle(" .. (shuffle and "x" or " ") .. "), X: exit")

                local prevTitle
                if (songQueue[queuePos - 1]) then prevTitle = songQueue[queuePos - 1][1] else prevTitle = songQueue[#songQueue][1] end
                if (#prevTitle > 9) then
                    prevTitle = string.sub(prevTitle, 1, 7) .. ".."
                end
                local nextTitle
                if (songQueue[queuePos + 1]) then nextTitle = songQueue[queuePos + 1][1] else nextTitle = songQueue[1][1] end
                if (#nextTitle > 9) then
                    nextTitle = string.sub(nextTitle, 1, 7) .. ".."
                end
                local queueString = "< " .. prevTitle .. string.rep(" ", screenWidth - #nextTitle - #prevTitle - 4) .. nextTitle .. " >"
                print("\n\n" .. queueString)

                parallel.waitForAny(pullKeyEvent, secondTimer)
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
                if (queuePos > 1) then
                    queuePos = queuePos - 1
                else
                    queuePos = #songQueue
                end

                os.queueEvent("song_interrupt")
                exit = true
            end
            if (key == keys.k) then
                if (queuePos < #songQueue) then
                    queuePos = queuePos + 1
                else
                    queuePos = 1
                end

                os.queueEvent("song_interrupt")
                exit = true
            end
            if (key == keys.r) then
                if (not shuffle) then
                    shuffle = true
                    --- shuffle queue, will be reset to regular order upon return to songListUI
                    -- remove current song from queue before shuffling
                    local song = songQueue[queuePos]
                    table.remove(songQueue, queuePos)
                    -- shuffle remaining queue (sort with random comparator lmao)
                    local function randomComparator(a, b)
                        math.randomseed()
                        return math.random() < 0.5
                    end
                    table.sort(songQueue, randomComparator)
                    -- insert current song at beginning of new queue
                    table.insert(songQueue, 1, song)
                    queuePos = 1
                else
                    shuffle = false

                    -- restore queuePos to currently playing song
                    queuePos = songQueue[queuePos][3]

                    -- restore queue order from current playlist
                    refreshSongQueue()
                end
            end
            if (key == keys.x) then
                os.queueEvent("song_interrupt")
                uiLayer = 1
                exit = true
            end
        end
    end


    repeat
        parallel.waitForAny(playSong, songUI, updateLastChunk)
    until exit
    --os.sleep(0.5)
end




---- main
local args = {...}
if (args[1]) then
    local chunkSize = math.tointeger(args[1])
    if (not chunkSize) then
        error("usage: brisket-player [segment size (in bytes)]")
    end

    urlPlayer.chunkSize = chunkSize
end

-- read from song_list.txt if exists
readCache(songList, songListPath)

-- read from playlists.txt if exists
readCache(playlists, playlistsPath)

-- build global playlist as first entry
playlists[1] = {"songs"}
for i=1, #songList do
    table.insert(playlists[1], i)
end

-- initialize with the global playlist open
currentPlaylist = 1


--- ui loop
while true do
    term.clear()

    if (uiLayer == 1) then
        songListUI()
    elseif (uiLayer == 2) then
        playlistsUI()
    elseif (uiLayer == 3) then
        songPlayerUI()
    else
        break
    end
end