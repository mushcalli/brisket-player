# brisket-player
a music streaming app for playing DFPWM files in CC:Tweaked (ver 1.100 and up)

## Features:
- Plays DFPWM files of any size from web-hosted raw media links (like from [here](https://github.com/mushcalli/computercraft/tree/main/dfpwm-files/music))
- Customizable song list and playlists
- Pausing, seeking, and shuffling
- Keyboard-based UI
- Tunable segment size with commandline argument for faster or slower internet speeds

## Screenshots:
<p align="middle">
  <img src=https://github.com/user-attachments/assets/2f4c5171-b27b-4693-8e38-100f69db524e width="400" />
  <img src=https://github.com/user-attachments/assets/eb554b3a-6ea9-459a-a092-57b757ed31aa width="400" />
</p>

## Installation and Usage:
### brisket-player
`wget https://github.com/mushcalli/brisket-player/raw/main/brisket-player.lua`

#### To run:

`brisket-player [segment size (in bytes)]`

The backend urlPlayer API will be installed when the program is run for the first time
### urlPlayer API

`wget https://github.com/mushcalli/brisket-player/raw/main/url-player.lua`

#### To import in Lua:
```lua
local urlPlayer = require("url-player")
```
#### To use:
```lua
urlPlayer.chunkSize
```
Segment size value (default 8192)<br><br>

```lua
urlPlayer.playFromUrl(string audioUrl, string interruptEvent, string chunkQueuedEvent = nil, int startOffset = 0, bool usePartialRequests = nil, int audioByteLength = nil)
```
Plays the DFPWM file at audioUrl, in segments if the source accepts partial GET requests, or in a single request if not
- returns true on interrupt, false otherwise
- chunkQueuedEvent: optional, if given will emit a dataless OS event with this name every time a new segment of audio is queued to the speaker
- startOffset: optional, if given will start playback from the startOffset'th byte of the file
- usePartialRequests: optional, usually found via an internal urlPlayer.pollUrl() call, but if given will skip the call and use the given value, only to be used for efficiency when audioUrl has already been polled externally
- audioByteLength: optional, see above
<br><br>

```lua
urlPlayer.pollUrl(string audioUrl)
```
Polls audioUrl for whether it supports partial GET requests, and if it does also polls the length of the file at audioUrl in bytes
- returns (bool supportsPartialRequests, int audioByteLength)
  - (false, nil) if partial requests not supported
  - nil if error (invalid url/get failed)

[![CC BY-NC-SA 4.0][cc-by-nc-sa-shield]][cc-by-nc-sa]

This work is licensed under a
[Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License][cc-by-nc-sa].

[![CC BY-NC-SA 4.0][cc-by-nc-sa-image]][cc-by-nc-sa]

[cc-by-nc-sa]: http://creativecommons.org/licenses/by-nc-sa/4.0/
[cc-by-nc-sa-image]: https://licensebuttons.net/l/by-nc-sa/4.0/88x31.png
[cc-by-nc-sa-shield]: https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg
