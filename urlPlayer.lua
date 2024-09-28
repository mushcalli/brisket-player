local dfpwm = require("cc.audio.dfpwm")

local speaker

local decoder = dfpwm.make_decoder()

local urlPlayer = {}

-- (chunkSize can be decreased on faster internet connections for faster initial buffering on song playback, or increased on slower ones for more consistent playback)
-- (max 16 * 1024)
urlPlayer.chunkSize = 16 * 1024


local function playChunk(chunk, interruptEvent)
    local buf = decoder(chunk)
    while not speaker.playAudio(buf) do
        local event, data = os.pullEvent()

        if (interruptEvent) then
            if (event == interruptEvent) then
                speaker.stop()
                return true
            end
        end
    end

    return false
end

--- stream audio chunks from url
-- returns true on interrupt, false otherwise
local function streamFromUrl(audioUrl, startOffset, audioByteLength, interruptEvent, chunkQueuedEvent)
    -- chunkQueuedEvent optional; see playFromUrl()

    --local startTimestamp = os.date("!%a, %d %b %Y %T GMT")

    local i = startOffset
    local prev_i
    --local maxByteOffset = urlPlayer.chunkSize * math.floor(audioByteLength / urlPlayer.chunkSize)
    local maxByteOffset = audioByteLength - math.fmod(audioByteLength, urlPlayer.chunkSize)

    local rangeEnd = math.min(i + urlPlayer.chunkSize - 1, audioByteLength - 1)
    --local chunkHandle, chunkErr = http.get(audioUrl, {["If-Unmodified-Since"] = startTimestamp, ["Range"] = "bytes=0-" .. rangeEnd})
    local chunkHandle, chunkErr = http.get(audioUrl, {["Range"] = "bytes=" .. i .. "-" .. rangeEnd})
    if (audioByteLength - startOffset > urlPlayer.chunkSize) then
        prev_i = i
        i = i + urlPlayer.chunkSize
        rangeEnd = math.min((i + urlPlayer.chunkSize) - 1, audioByteLength - 1)
        --local nextChunkHandle, nextErr = http.get(audioUrl, {["If-Unmodified-Since"] = startTimestamp, ["Range"] = "bytes=" .. i .. "-" .. rangeEnd})
        local nextChunkHandle, nextErr = http.get(audioUrl, {["Range"] = "bytes=" .. i .. "-" .. rangeEnd})
        while (i <= maxByteOffset) do
            -- return if get error
            if (not chunkHandle) then
                print("get failed :( \"" .. chunkErr .. "\"")
                if (nextChunkHandle) then
                    nextChunkHandle.close()
                end
                return false
            end
            if (not nextChunkHandle) then
                print("get failed :( \"" .. nextErr .. "\"")
                chunkHandle.close()
                return false
            end
            --[[if (chunkHandle.getResponseCode() == 412 or nextChunkHandle.getResponseCode() == 412) then
                print("get failed: file modified :(")
                chunkHandle.close()
                nextChunkHandle.close()
                return
            end]]
            if (chunkHandle.getResponseCode() ~= 206 or nextChunkHandle.getResponseCode() ~= 206) then
                print("get request failed :( (" .. chunkHandle.getResponseCode() .. ", " .. nextChunkHandle.getResponseCode() .. ")")
                chunkHandle.close()
                nextChunkHandle.close()
                return false
            end

            --[[local chunk = chunkHandle.readAll()
            local buf = decoder(chunk)
            while (not speaker.playAudio(buf)) do
                local event, data = os.pullEvent()
        
                if (interruptEvent) then
                    if (event == interruptEvent) then
                        speaker.stop()
                        chunkHandle.close()
                        nextChunkHandle.close()
                        return
                    end
                end
            end]]

            -- play chunk once speaker can receieve it, catch interrupts
            -- (chunk run time ~2.7s for default chunkSize of 16kb)
            local chunk = chunkHandle.readAll()

            local interrupt = playChunk(chunk, interruptEvent)
            if (interrupt) then
                chunkHandle.close()
                nextChunkHandle.close()
                return true
            end

            if (chunkQueuedEvent) then
                os.queueEvent(chunkQueuedEvent, prev_i, math.floor(os.clock()))
            end

            -- increment, get next chunk while current is playing
            chunkHandle.close()
            chunkHandle = nextChunkHandle
            prev_i = i
            i = i + urlPlayer.chunkSize
            rangeEnd = math.min(i + urlPlayer.chunkSize - 1, audioByteLength - 1)
            --nextChunkHandle, nextErr = http.get(audioUrl, {["If-Unmodified-Since"] = startTimestamp, ["Range"] = "bytes=" .. i .. "-" .. rangeEnd})
            nextChunkHandle, nextErr = http.get(audioUrl, {["Range"] = "bytes=" .. i .. "-" .. rangeEnd})
        end
    end

    -- play last chunk
    local chunk = chunkHandle.readAll()

    playChunk(chunk, interruptEvent)
    chunkHandle.close()

    if (chunkQueuedEvent) then
        os.queueEvent(chunkQueuedEvent, prev_i, math.floor(os.clock()))
    end

    return false
end

-- returns true on interrupt, false otherwise
function urlPlayer.playFromUrl(audioUrl, interruptEvent, chunkQueuedEvent, startOffset, usePartialRequests, audioByteLength)
    -- chunkQueuedEvent optional, if given will send that event just before playing each chunk, along with { chunk byte offset, chunk queued time (based on os.clock()) }
    -- last 2 args optional, only to be used if url has been polled externally

    speaker = peripheral.find("speaker")
    if (not speaker) then error("error: speaker not found") end

    -- startOffset will be ignored if partial requests aren't supported, the song will just be played from the beginning
    startOffset = startOffset or 0

    -- if not provided, poll url for usePartialRequests, audioByteLength
    if (usePartialRequests == nil or audioByteLength == nil) then
        local pollResponse, polledLength = urlPlayer.pollUrl(audioUrl)

        if (pollResponse == nil) then -- if pollUrl returned error, exit
            return false
        end

        usePartialRequests = pollResponse
        audioByteLength = polledLength
    end

    if (startOffset < 0 or startOffset > audioByteLength - 1) then
        print("invalid startOffset (" .. startOffset .. ")")
        return false
    end


    --- playback
    if (usePartialRequests) then
        local interrupt = streamFromUrl(audioUrl, startOffset, audioByteLength, interruptEvent, chunkQueuedEvent)
        return interrupt
    else
        --- play from single get request
        local response = http.get(audioUrl)
        if (not response) then
            print("get request failed :(")
            return
        end

        local chunk = response.read(urlPlayer.chunkSize)
        local i = 0
        while (chunk) do
            if (chunkQueuedEvent) then
                os.queueEvent(chunkQueuedEvent, i, math.floor(os.clock()))
            end

            local interrupt = playChunk(chunk, interruptEvent)
            if (interrupt) then
                -- close response handle and exit early
                response.close()
                return true
            end

            chunk = response.read(urlPlayer.chunkSize)
            i = i + urlPlayer.chunkSize
        end

        -- close response handle when done
        response.close()
        return false
    end
end

--- returns { supportsPartialRequests, audioByteLength }
-- { false, nil } if partial requests not supported
-- { nil, err } if error (invalid url/get failed)
function urlPlayer.pollUrl(audioUrl)
    -- head request
    http.request({url = audioUrl, method = "HEAD"})
    local event, _url, response
    repeat
        event, _url, response = os.pullEvent()
    until (event == "http_success" or event == "http_failure") and _url == audioUrl
    if (event == "http_failure") then
        print(response)
        return nil
    end


    local headers = response.getResponseHeaders()
    --local audioByteLength = headers["Content-Length"]
    ---- BROKEN FOR GITHUB RAW LINKS ^^ idk why github isnt properly implementing the Content-Length headers in their HEAD request responses :(((
    local supportsPartialRequests = (headers["Accept-Ranges"] and headers["Accept-Ranges"] ~= "none")
    if (not supportsPartialRequests) then
        return false, nil
    end


    -- request the first byte to scrape the full file's Content-Length from lmfao
    local byteHandle, err = http.get(audioUrl, {["Range"] = "bytes=0-0"})
    if (not byteHandle) then
        print("byte get request failed :( (".. err .. ")")
        return nil
    end
    if (byteHandle.getResponseCode() ~= 206) then
        print("byte get request failed :( (".. byteHandle.getResponseCode() .. ")")
        byteHandle.close()
        return nil
    end
    local _header = byteHandle.getResponseHeaders()["Content-Range"]
    if (not _header) then
        print("byte get request failed :( (no Content-Range)")
        byteHandle.close()
        return nil
    end
    local _, __, audioByteLength = string.find(_header, "([^%/]+)$")
    audioByteLength = tonumber(audioByteLength)


    return true, audioByteLength
end


return urlPlayer