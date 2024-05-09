local mf = require("morefonts")
local pretty = require ("cc.pretty")
local dfpwm = require("cc.audio.dfpwm")

--Set peripheral names here please

local bigcolourmonitor = peripheral.wrap("monitor_0") --> The main, 4x4 advanced monitor
bigcolourmonitor.setTextScale(0.5)

local greymonitor = peripheral.wrap("monitor_1") --> The 4x1 normal monitor below the bigcolourmonitor (do NOT use an advanced monitor here)
greymonitor.setTextScale(0.5)
greymonitor.clear()

local smallcolourmonitor = peripheral.wrap("monitor_2") --> The 4x1 advanced monitor below the grey monitor
smallcolourmonitor.setTextScale(0.5)

local speakermonitor = peripheral.wrap("monitor_3") --> The 1x2 vertical monitor for audio controls above the speakers
speakermonitor.setTextScale(0.5)

local diskdrive = peripheral.wrap("drive_0") --> The disk drive for using floppy disks

local speaker = peripheral.wrap("speaker_0") --> The speaker for playing audio

--[[Those are all the changes you need to make to the code. The positioning of the peripherals doesn't matter as much as their dimensions do,
but for the intended experience, it is advised to follow the setup in the images provided on pinestore]]

local musicdata = {}
local albumnum = 0
local albummarquee, disklabelmarquee, greymarquee = false, false, false
local menustate, trackpage, albumpage, track, album = "albums", 1, 1, 0, 0
local playpause, shuffle, loop = false, false, false
local leftarrowwobble, rightarrowwobble = false, false
local volumeupwobble, volumedownwobble = false, false
local albumplaying, trackplaying = 0, 0
local tempalbumname, tempdisklabel, tempdisplayphrase
local progress, duration, decoder, audiohandle, queuepos = 0, 0
local theme = {["themenum"] = 1, 0xF0F0F0, 0x999999, 0x4C4C4C, 0x111111}
local queue = {}
local displayphrase = "Blockman"
local volume = 1.5

local function changeTheme(themenum)

    if fs.exists("/disk/theme.blockman") then
        theme = textutils.unserialise(fs.open("/disk/theme.blockman", "r").readAll())
    end

    if themenum then
        theme["themenum"] = themenum
    end

    if theme["themenum"]==1 then
        theme[1], theme[2], theme[3], theme[4] = 0xF0F0F0, 0x999999, 0x4C4C4C, 0x111111
    elseif theme["themenum"]==2 then
        theme[1], theme[2], theme[3], theme[4] = 0xEB6590, 0xC565EB, 0x6D65EB, 0x111111
    elseif theme["themenum"]==3 then
        theme[1], theme[2], theme[3], theme[4] = 0xEBBE65, 0xEB9364, 0xEB6565, 0x111111
    elseif theme["themenum"]==4 then
        theme[1], theme[2], theme[3], theme[4] = 0x92EB65, 0xEBE465, 0xEBC465, 0x111111
    elseif theme["themenum"]==5 then
        theme[1], theme[2], theme[3], theme[4] = 0x65EBDD, 0x65EB82, 0xB1EB65, 0x111111
    elseif theme["themenum"]==6 then
        theme[1], theme[2], theme[3], theme[4] = 0xBA65EB, 0x6567EB, 0x65BCEB, 0x111111
    elseif theme["themenum"]==7 then
        theme[1], theme[2], theme[3], theme[4] = 0xffffff, 0xfd9855, 0xd161a2, 0x111111
    elseif theme["themenum"]==8 then
        theme[1], theme[2], theme[3], theme[4] = 0xffffff, 0x5bcefa, 0xf5a9b8, 0x111111
    end

    if diskdrive.isDiskPresent() then
        local handle = fs.open("/disk/theme.blockman", "w+")
        handle.write(textutils.serialise(theme))
        handle.close()
    end
end

local function setTheme()
    bigcolourmonitor.setPaletteColor(colours.white, theme[1])
    bigcolourmonitor.setPaletteColor(colours.lightGrey, theme[2])
    bigcolourmonitor.setPaletteColor(colours.grey, theme[3])
    bigcolourmonitor.setPaletteColor(colours.black, theme[4])

    smallcolourmonitor.setPaletteColor(colours.white, theme[1])
    smallcolourmonitor.setPaletteColor(colours.black, theme[4])

    speakermonitor.setPaletteColor(colours.white, theme[1])
end

local function formatTime(seconds)
    local m = math.floor(seconds/60)
    if m < 10 then m = "0"..m end
    local s = math.floor(seconds%60)
    if s < 10 then s = "0"..s end
    return m..":"..s
end

local function getDuration()
    duration = audiohandle.seek("end")/6000
    audiohandle.seek("set", 0)
end

local function getData(url)
  local handle, err = http.get(url)
  if not handle then error(err, 2) end

  local data = handle.readAll()
  handle.close()

  return data
end

local function writeData(filename, data)
  local handle, err = fs.open(filename, "w")
  if not handle then error(err, 2) end

  handle.write(data)
  handle.close()
end

local function diskRemove()
    musicdata = {}
    trackpage, albumpage = 1, 1
    album, track, albumplaying, trackplaying, progress = 0, 0, 0, 0, 0
    queuepos = nil
    menustate = "albums"
    displayphrase = "Blockman"
    queue = {}
    playpause, shuffle, loop = false, false, false
    albummarquee = false
    greymarquee = false
    disklabelmarquee = false
    greymonitor.clear()
    theme = {["themenum"] = 1, 0xF0F0F0, 0x999999, 0x4C4C4C, 0x111111}
    setTheme()
end 

local function diskCheck()
    if fs.exists("disk/musicdata.blockman") then
        local file = fs.open("disk/musicdata.blockman", "r")
        local contents = file.readAll()
        file.close()
        musicdata = textutils.unserialise(contents)
        local i = 1
        while musicdata[i] do
            i = i+1
        end
        albumnum = i - 1
    else
        musicdata = {}
        albumnum = 0
    end
    musicdata["disklabel"] = diskdrive.getDiskLabel()
    tempdisklabel = diskdrive.getDiskLabel() and diskdrive.getDiskLabel().."   "
    if fs.exists("/disk/theme.blockman") then
        changeTheme()
        setTheme()
    end
end

local function editMusicData()
    local function question(text)
        term.setTextColour(colours.purple)
        print(text)
        term.setTextColour(colours.white)
    end
    local function statement(text)
        term.setTextColour(colours.yellow)
        print(text)
        term.setTextColour(colours.white)
    end
    while true do
        question("What would you like to edit?\n(Enter \"disklabel\", \"album\", \"track\", or \"abort\")")
        local temp = read()
        if temp=="abort" then
            question("Would you like to save changes?\n(Enter \"yes\" or \"no\")")
            local temp = read()
            if temp=="yes" then
                local serialisedmusicdata = textutils.serialise(musicdata)
                writeData("disk/musicdata.blockman", serialisedmusicdata)
                statement("Saved changes")
                menustate = "settings"
                break
            elseif temp=="no" then
                statement("Discarded Changes")
                menustate = "settings"
                break
            else
                statement("Invalid choice")
            end
        elseif temp=="disklabel" then
            question("Enter the new disk label: ")
            musicdata["disklabel"] = read()
            diskdrive.setDiskLabel(musicdata["disklabel"])
            statement("Changed disk label")
        elseif temp=="album" then
            question("Enter the index of the album you'd like to edit: ")
            local i = tonumber(read())
            if i<=#musicdata then
                statement("Selected album named \""..musicdata[i]["albumname"].."\"")
                question("What would you like to edit about this album?\n(Enter \"art\", \"name\", \"artistname\", \"MOVE\", \"DELETE\", or, to abort, anything else)")
                local temp = read()
                if temp=="art" then
                    question("Enter the new link to the artwork for the album: ")
                    musicdata[i]["albumartlink"] = read()
                    statement("Changed album artwork link")
                elseif temp=="name" then
                    question("Enter the new name for the album: ")
                    musicdata[i]["albumname"] = read()
                    statement("Changed album name")
                elseif temp=="artistname" then
                    question("Enter the new name for the artist of the album: ")
                    musicdata[i]["albumartistname"] = read()
                    statement("Changed album artist name")
                elseif temp=="MOVE" then
                    question("Enter the new position for the album: ")
                    local k = tonumber(read())
                    if k<=#musicdata and k~=i then
                        table.insert(musicdata, k, table.remove(musicdata, i))
                        statement("Moved album")
                    else
                        statement("Invalid position")
                    end
                elseif temp=="DELETE" then
                    table.remove(musicdata, i)
                    statement("Deleted album")
                else
                    statement("Aborted")
                end
            else
                statement("No album found at that index")
            end
        elseif temp=="track" then
            question("Enter the index of the album in which the track belongs: ")
            local i = tonumber(read())
            if i<=#musicdata then
                statement("Selected album named \""..musicdata[i]["albumname"].."\"")
                question("Enter the index of the track you'd like to edit:\nNote: enter "..tostring(#musicdata[i]+1).." to add another track")
                local j = tonumber(read())
                if j<=#musicdata[i] then
                    statement("Selected track named \""..musicdata[i][j]["trackname"].."\"")
                    question("What would you like to edit about this track?\n(Enter \"link\", \"name\", \"artistname\", \"MOVE\", \"DELETE\", or, to abort, anything else)")
                    local temp = read()
                    if temp=="link" then
                        question("Enter the new link for the track: ")
                        musicdata[i][j]["tracklink"] = read()
                        statement("Changed track link")
                    elseif temp=="name" then
                        question("Enter the new name for the track: ")
                        musicdata[i][j]["trackname"] = read()
                        statement("Changed track name")
                    elseif temp=="artistname" then
                        question("Enter the new name for the artist of the track: ")
                        musicdata[i][j]["trackartistname"] = read()
                        statement("Changed track artist name")
                    elseif temp=="MOVE" then
                        question("Enter the new position for the track: ")
                        local k = tonumber(read())
                        if k<=#musicdata[i] and k~=j then
                            table.insert(musicdata[i], k, table.remove(musicdata[i], j))
                            statement("Moved track")
                        else
                            statement("Invalid position")
                        end
                    elseif temp=="DELETE" then
                        table.remove(musicdata[i], j)
                        statement("Deleted track")
                    else
                        statement("Aborted")
                    end
                elseif j==#musicdata[i]+1 then
                    musicdata[i][j] = {}
                    question("Enter the name of the track: ")
                    musicdata[i][j]["trackname"] = read()
                    question("Enter the name of the artist(s) for the track: ")
                    musicdata[i][j]["trackartistname"] = read()
                    question("Enter the link for the track: ")
                    musicdata[i][j]["tracklink"] = read()
                    statement("Track added")
                else
                    statement("No track found at that index")
                end
            else
                statement("No album found at that index")
            end
        else
            statement("Invalid choice\nNote: text is case-sensitive")
        end
    end
end

local function addMusicData()
    local function question(text)
        term.setTextColour(colours.purple)
        print(text)
        term.setTextColour(colours.white)
    end
    if not musicdata["disklabel"] then
        question("Enter the disk label: ")
        musicdata["disklabel"] = read()
        diskdrive.setDiskLabel(musicdata["disklabel"])
    end
    local i = albumnum + 1
    while true do
        musicdata[i] = {}
        question("Enter the name of the album: ")
        musicdata[i]["albumname"] = read()
        question("Enter the name of the artist for the album: ")
        musicdata[i]["albumartistname"] = read()
        question("Enter the link to the artwork for the album: ")
        musicdata[i]["albumartlink"] = read()
        local j = 1
        while true do
            musicdata[i][j] = {}
            question("Enter the name of the track: ")
            musicdata[i][j]["trackname"] = read()
            question("Enter the name of the artist(s) for the track: ")
            musicdata[i][j]["trackartistname"] = read()
            question("Enter the link for the track: ")
            musicdata[i][j]["tracklink"] = read()
            question("To finish writing tracks, type \"stop.\", otherwise hit enter")
            local temp = read()
            if temp == "stop." then
                break
            end
            j = j+1
        end
        question("To finish writing albums, type \"stop.\"")
        local temp = read()
        if temp == "stop." then
            break
        end
        i = i+1
    end
    local serialisedmusicdata = textutils.serialise(musicdata)
    writeData("disk/musicdata.blockman", serialisedmusicdata)
    menustate = "settings"
end

local function bimgDraw(bimg, x, y, mon)
    local frame = bimg[1]
    for k,line in pairs(frame) do
        mon.setCursorPos(x,y+k-1)
        mon.blit(line[1], line[2], line[3])
    end
end

local function artDisplay(data)
    bigcolourmonitor.clear()
    local artdata = textutils.unserialise(data)

    for i=0,15 do
        bigcolourmonitor.setPaletteColour(2^i,artdata.palette[i][1])
    end

    bimgDraw(artdata, 1, 1, bigcolourmonitor)
end

local function iconDisplay(mon, iconname, xpos, ypos)
    local file = fs.open("/Icons/"..iconname..".bimg", "r")
    local contents = file.readAll()
    file.close()
    local icondata = textutils.unserialise(contents)

    bimgDraw(icondata, xpos, ypos, mon)
end

local function refreshGrey()
    mf.writeOn(greymonitor, string.rep(" ", 28), 1, 2, {scale = 1})
    greymarquee = false
    if displayphrase=="Loading Track..." or displayphrase=="Blockman" or displayphrase=="Error Loading Track" then
        mf.writeOn(greymonitor, displayphrase, nil, 2, {scale = 1, condense = true})
    else
        displayphrase = musicdata[albumplaying][trackplaying]["trackname"]
        if playpause then 
            displayphrase = "Now Playing: "..displayphrase
            tempdisplayphrase = string.rep(displayphrase.."   ", 2)
            greymarquee = true
        else
            displayphrase = "Paused: "..displayphrase
            if #displayphrase < 26 then
                mf.writeOn(greymonitor, displayphrase, nil, 2, {scale = 1})
            else
                mf.writeOn(greymonitor, string.sub(displayphrase, 1, 22).."...", nil, 2, {scale = 1})
            end
        end
    end
end

local function refreshSpeaker()
    speakermonitor.clear()
    speakermonitor.setTextColour(colours.lightGrey)
    iconDisplay(speakermonitor, "plus", 5, 2)
    iconDisplay(speakermonitor, "minus", 5, 18)
    speakermonitor.setTextColour(colours.white)
    mf.writeOn(speakermonitor, volume, nil, nil, {scale = 2, condense = true, dy = 1})
end

local function refreshBigColour()
    albummarquee = false
    disklabelmarquee = false
    bigcolourmonitor.clear()
    if menustate=="albumart" then
        mf.writeOn(bigcolourmonitor, "Loading Album Art...", nil, nil, {Scale = 2, condense = true})
        local handle = http.get(musicdata[album]["albumartlink"])
        if not handle then
            mf.writeOn(bigcolourmonitor, "Error Loading Album Art", nil, nil, {Scale = 2, condense = true})
        else
            artDisplay(handle.readAll())
        end
    elseif menustate=="tracks" then
        setTheme()

        bigcolourmonitor.setTextColour(colours.white)
        if string.len(musicdata[album]["albumname"]) < 13 then
            mf.writeOn(bigcolourmonitor, musicdata[album]["albumname"], nil, 2, {scale = 2})
        else
            albummarquee = true
        end

        bigcolourmonitor.setTextColour(colours.lightGrey)
        if string.len(musicdata[album]["albumartistname"]) < 24 then
            mf.writeOn(bigcolourmonitor, "- "..musicdata[album]["albumartistname"], 72-(3*string.len(musicdata[album]["albumartistname"])), 9, {scale = 1})
        else
            mf.writeOn(bigcolourmonitor, "- "..string.sub(musicdata[album]["albumartistname"], 1, 20).."...", 3, 9, {scale = 1})
        end

        bigcolourmonitor.setTextColour(colours.grey)
        bigcolourmonitor.setCursorPos(1,13)
        bigcolourmonitor.write(string.rep("\131",80))
        bigcolourmonitor.setTextColour(colours.lightGrey)

        local linenum = 14
        for i=1,5 do
            local t = 5*(trackpage-1)+i
            if t <= #musicdata[album] then
                if t==track then
                    bigcolourmonitor.setTextColour(colours.white)
                end
                if string.len(t..". "..musicdata[album][t]["trackname"]) < 26 then
                    mf.writeOn(bigcolourmonitor, t..". "..musicdata[album][t]["trackname"], 2, linenum, {scale = 1, condense = true})
                else
                    mf.writeOn(bigcolourmonitor, t..". "..string.sub(musicdata[album][t]["trackname"], 1, 21-string.len(t)).."...", 2, linenum, {scale = 1, condense = true})
                end
                linenum = linenum + 3
                bigcolourmonitor.setTextColour(colours.grey)
                if t==track then
                    bigcolourmonitor.setTextColour(colours.lightGrey)
                end
                if string.len(musicdata[album][t]["trackartistname"]) < 26 then
                    mf.writeOn(bigcolourmonitor, musicdata[album][t]["trackartistname"], 2, linenum, {scale = 1, condense = true})
                else
                    mf.writeOn(bigcolourmonitor, string.sub(musicdata[album][t]["trackartistname"],1 , 22).."...", 2, linenum, {scale = 1, condense = true})
                end
                linenum = linenum + 3
                bigcolourmonitor.setTextColour(colours.grey)
                bigcolourmonitor.setCursorPos(1,linenum)
                bigcolourmonitor.write(string.rep("\131",80))
                bigcolourmonitor.setTextColour(colours.lightGrey)
                linenum = linenum + 1
            end
        end
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, "<", 2, 50, {dy = -1, scale = 1})
        mf.writeOn(bigcolourmonitor, "menu", nil, 50, {dy = -1, scale = 1, condense = true})
        mf.writeOn(bigcolourmonitor, ">", 76, 50, {dy = -1, scale = 1})

    elseif menustate=="albums" then
        if diskdrive.isDiskPresent() then
            bigcolourmonitor.setTextColour(colours.white)
            if musicdata["disklabel"] then
                if string.len(musicdata["disklabel"]) < 13 then
                    mf.writeOn(bigcolourmonitor, musicdata["disklabel"], nil, 2, {scale = 2})
                else
                    disklabelmarquee = true
                end
            else 
                mf.writeOn(bigcolourmonitor, "Empty Disk", nil, 2, {scale = 2})
            end

            bigcolourmonitor.setTextColour(colours.lightGrey)
            if string.len(tostring(diskdrive.getDiskID())) < 17 then
                mf.writeOn(bigcolourmonitor, "Disk ID: "..tostring(diskdrive.getDiskID()), 52-(3*string.len(tostring(diskdrive.getDiskID()))), 9, {scale = 1})
            else
                mf.writeOn(bigcolourmonitor, "Disk ID: "..string.sub(tostring(diskdrive.getDiskID()), 1, 14).."...", 3, 9, {scale = 1})
            end

            bigcolourmonitor.setTextColour(colours.grey)
            bigcolourmonitor.setCursorPos(1,13)
            bigcolourmonitor.write(string.rep("\131",80))
            bigcolourmonitor.setTextColour(colours.lightGrey)

            local linenum = 14
            for i=1,5 do
                local t = 5*(albumpage-1)+i
                if t <= #musicdata then
                    if t==albumplaying then
                        bigcolourmonitor.setTextColour(colours.white)
                    end
                    if string.len(musicdata[t]["albumname"]) < 26 then
                        mf.writeOn(bigcolourmonitor, musicdata[t]["albumname"], 2, linenum, {scale = 1, condense = true})
                    else
                        mf.writeOn(bigcolourmonitor, string.sub(musicdata[t]["albumname"], 1, 22).."...", 2, linenum, {scale = 1, condense = true})
                    end
                    linenum = linenum + 3
                    bigcolourmonitor.setTextColour(colours.grey)
                    if t==albumplaying then
                        bigcolourmonitor.setTextColour(colours.lightGrey)
                    end
                    if string.len(musicdata[t]["albumartistname"]) < 26 then
                        mf.writeOn(bigcolourmonitor, musicdata[t]["albumartistname"], 2, linenum, {scale = 1, condense = true})
                    else
                        mf.writeOn(bigcolourmonitor, string.sub(musicdata[t]["albumartistname"],1 , 22).."...", 2, linenum, {scale = 1, condense = true})
                    end
                    linenum = linenum + 3
                    bigcolourmonitor.setTextColour(colours.grey)
                    bigcolourmonitor.setCursorPos(1,linenum)
                    bigcolourmonitor.write(string.rep("\131",80))
                    bigcolourmonitor.setTextColour(colours.lightGrey)
                    linenum = linenum + 1
                end
            end
            bigcolourmonitor.setTextColour(colours.white)
            mf.writeOn(bigcolourmonitor, "<", 2, 50, {dy = -1, scale = 1})
            mf.writeOn(bigcolourmonitor, "settings", nil, 50, {dy = -1, scale = 1, condense = true})
            mf.writeOn(bigcolourmonitor, ">", 76, 50, {dy = -1, scale = 1})
        else
            bigcolourmonitor.setBackgroundColour(colours.grey)
            bigcolourmonitor.setTextColour(colours.white)
            mf.writeOn(bigcolourmonitor, string.rep(" ", 25).."No Disk Present"..string.rep(" ", 25), nil, nil, {scale = 1})
            bigcolourmonitor.setBackgroundColour(colours.black)
        end
    elseif menustate=="settings" then
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, "Settings", nil, 2, {scale = 2, dy = 1, condense = true})
        bigcolourmonitor.setTextColour(colours.grey)
        bigcolourmonitor.setCursorPos(1,9)
        bigcolourmonitor.write(string.rep("\131",80))
        bigcolourmonitor.setTextColour(colours.white)
        iconDisplay(bigcolourmonitor, "about", 4, 16)
        iconDisplay(bigcolourmonitor, "addmusic", 32, 16)
        iconDisplay(bigcolourmonitor, "discord", 61, 16)
        iconDisplay(bigcolourmonitor, "themes", 16, 33)
        iconDisplay(bigcolourmonitor, "edit", 48, 33)
        mf.writeOn(bigcolourmonitor, "return", nil, 50, {dy = -1, scale = 1, condense = true})
    elseif menustate=="about" then
        mf.writeOn(bigcolourmonitor, "About", nil, 2, {scale = 2, condense = true})
        bigcolourmonitor.setTextColour(colours.grey)
        bigcolourmonitor.setCursorPos(1,9)
        bigcolourmonitor.write(string.rep("\131",80))
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, "I'm Blockman, the Minecraft Walkman!\nAdd music (.dfpwm) and album art (.bimg) to me as direct download links.\n\nbimg convertor, 4x4 monitors:\nhttps://masongulu.github.io/js-bimg-generator/\n\ndfpwm convertor:\nhttps://music.madefor.cc", 2, 11, {scale = 1, condense = true, wrapWidth = 158})
        bigcolourmonitor.setTextColour(colours.grey)
        mf.writeOn(bigcolourmonitor, "(click anywhere to exit)", nil, 49, {scale = 1, condense = true})
    elseif menustate=="addmusic" then
        bigcolourmonitor.setBackgroundColour(colours.grey)
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, string.rep(" ", 25).."Adding Music Data..."..string.rep(" ", 25), nil, nil, {scale = 1})
        bigcolourmonitor.setBackgroundColour(colours.black)
        addMusicData()
        diskRemove()
        diskCheck()
        refreshBigColour()
    elseif menustate=="socials" then
        mf.writeOn(bigcolourmonitor, "Socials", nil, 2, {scale = 2, condense = true})
        bigcolourmonitor.setTextColour(colours.grey)
        bigcolourmonitor.setCursorPos(1,9)
        bigcolourmonitor.write(string.rep("\131",80))
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, "Hi! I'm Ella, the creator of Blockman.\nThis project was made possible by lots of support from the ComputerCraft community, and Michiel's handy morefonts library. For help and bug reports, message me on Discord:\n@ellabunnyxo or @bluerella\n\nLove, Ella <3", 2, 11, {scale = 1, condense = true, wrapWidth = 158})
        bigcolourmonitor.setTextColour(colours.grey)
        mf.writeOn(bigcolourmonitor, "(click anywhere to exit)", nil, 49, {scale = 1, condense = true})
    elseif menustate=="edit" then
        bigcolourmonitor.setBackgroundColour(colours.grey)
        bigcolourmonitor.setTextColour(colours.white)
        mf.writeOn(bigcolourmonitor, string.rep(" ", 25).."Editing Music Data..."..string.rep(" ", 25), nil, nil, {scale = 1})
        bigcolourmonitor.setBackgroundColour(colours.black)
        editMusicData()
        diskRemove()
        diskCheck()
        refreshBigColour()
    end
end

local function refreshSmallColour()
    smallcolourmonitor.clear()
    if playpause==false then
        iconDisplay(smallcolourmonitor, "play", 32, 1)
    else
        iconDisplay(smallcolourmonitor, "pause", 32, 1)
    end
    iconDisplay(smallcolourmonitor, "skip", 48, 1)
    iconDisplay(smallcolourmonitor, "rewind", 16, 1)
    if shuffle==false then
        iconDisplay(smallcolourmonitor, "shuffleOFF", 1, 1)
    else
        iconDisplay(smallcolourmonitor, "shuffleON", 1, 1)
    end
    if loop==false then
        iconDisplay(smallcolourmonitor, "loopOFF", 64, 1)
    else
        iconDisplay(smallcolourmonitor, "loopON", 64, 1)
    end
end

local function changeTrack()
    playpause = false
    refreshSmallColour()
    displayphrase = "Loading Track..."
    refreshGrey()
    decoder = dfpwm.make_decoder()
    audiohandle = http.get(musicdata[albumplaying][trackplaying]["tracklink"])
    if audiohandle then
        getDuration()
        displayphrase = " "
        refreshGrey()
        greymonitor.setTextColour(colours.grey)
        mf.writeOn(greymonitor, formatTime(duration), 63, 8, {scale = 1, dx = 1})
        greymonitor.setTextColour(colours.white)
        progress = 0
    else
        displayphrase = "Error Loading Track"
        refreshGrey()
    end
end

local function playNext()
    if queuepos==#queue then
        queuepos = 1
        trackplaying = queue[queuepos]
        track = trackplaying
        refreshBigColour()
        changeTrack()
        if loop then
            if audiohandle then
                playpause = true
            end
            refreshSmallColour()
            refreshGrey()
        end
    else
        queuepos = queuepos + 1
        trackplaying = queue[queuepos]
        track = trackplaying
        refreshBigColour()
        changeTrack()
        if audiohandle then
            playpause = true
        end
        refreshSmallColour()
        refreshGrey()
    end
end

local function playPrevious()
    if progress > 5 then
        progress = 0
        changeTrack()
    else
        if queuepos==1 then
            queuepos = #queue
        else
            queuepos = queuepos - 1
        end
        trackplaying = queue[queuepos]
        track = trackplaying
        refreshBigColour()
        changeTrack()
    end
    if displayphrase ~= "Error Loading Track" then
        playpause = true
    end
    refreshGrey()
end

local function makeQueue(album)
    queue = {}
    if album~=0 then
        queuepos = trackplaying
        for i = 1, #musicdata[album] do
            queue[i] = i 
        end
        if shuffle then
            queue[1] = trackplaying
            queuepos = 1
            for i = 2, #musicdata[album] do
                local r, t = math.random(2, #musicdata[album])
                t = queue[i]
                queue[i] = queue[r]
                queue[r] = t
            end
        end
    end
end

local function trackTouch(k)
    track = 5*(trackpage-1)+k
    if albumplaying~=album then
        makeQueue(album)
        if trackplaying==track then
            playpause = false
            refreshSmallColour()
            albumplaying = album
            refreshBigColour()
            changeTrack()
        end
    end
    if trackplaying~=track then
        playpause = false
        refreshSmallColour()
        trackplaying = track
        queuepos = trackplaying
        albumplaying = album
        refreshBigColour()
        changeTrack()
    end
    if shuffle then
        makeQueue(album)
    end
    if displayphrase ~= "Error Loading Track" then
        playpause = true
    end
    refreshGrey()
end

local function albumTouch(k)
    album = 5*(albumpage-1)+k
    if album==albumplaying then
        track = trackplaying
    else
        track = 0
    end
    trackpage = 1
    menustate = "tracks"
    tempalbumname = musicdata[album]["albumname"].."   "
end

local function touchBigColour(x, y)
    local mouseX, mouseY = x, y
    if menustate=="albumart" then
        menustate = "tracks"
    elseif menustate=="tracks" then
        if mouseY < 13 then
            menustate = "albumart"
        elseif mouseY > 13 and mouseY < 20 and 5*(trackpage-1)+1 <= #musicdata[album] then
            trackTouch(1)
        elseif mouseY > 20 and mouseY < 27 and 5*(trackpage-1)+2 <= #musicdata[album] then
            trackTouch(2)
        elseif mouseY > 27 and mouseY < 34 and 5*(trackpage-1)+3 <= #musicdata[album] then
            trackTouch(3)
        elseif mouseY > 34 and mouseY < 41 and 5*(trackpage-1)+4 <= #musicdata[album] then
            trackTouch(4)
        elseif mouseY > 41 and mouseY < 48 and 5*(trackpage-1)+5 <= #musicdata[album] then
            trackTouch(5)
        elseif mouseY > 48 then
            if mouseX < 6 then
                if trackpage==1 then
                    leftarrowwobble = true
                else
                    trackpage = trackpage-1
                end
            elseif mouseX > 33 and mouseX < 47 then
                menustate = "albums"
                tempdisklabel = musicdata["disklabel"].."   "
            elseif mouseX > 73 then
                if trackpage==math.ceil(#musicdata[album]/5) then
                    rightarrowwobble = true
                else
                    trackpage = trackpage+1
                end
            end
        end
    elseif menustate=="albums" then
        if mouseY > 13 and mouseY < 20 and 5*(albumpage-1)+1 <= #musicdata then
            albumTouch(1)
        elseif mouseY > 20 and mouseY < 27 and 5*(albumpage-1)+2 <= #musicdata then
            albumTouch(2)
        elseif mouseY > 27 and mouseY < 34 and 5*(albumpage-1)+3 <= #musicdata then
            albumTouch(3)
        elseif mouseY > 34 and mouseY < 41 and 5*(albumpage-1)+4 <= #musicdata then
            albumTouch(4)
        elseif mouseY > 41 and mouseY < 48 and 5*(albumpage-1)+5 <= #musicdata then
            albumTouch(5)
        elseif mouseY > 48 then
            if mouseX < 6 then
                if albumpage==1 or #musicdata==0 then
                    leftarrowwobble = true
                else
                    albumpage = albumpage-1
                end
            elseif mouseX > 27 and mouseX < 53 then
                menustate = "settings"
            elseif mouseX > 73 then
                if albumpage==math.ceil(#musicdata/5) or #musicdata==0 then
                    rightarrowwobble = true
                else
                    albumpage = albumpage+1
                end
            end
        end
    elseif menustate=="settings" then
        if mouseY > 15 and mouseY < 26 then
            if mouseX > 3 and mouseX < 20 then
                menustate = "about"
            elseif mouseX > 31 and mouseX < 48 then
                menustate = "addmusic"
            elseif mouseX > 60 and mouseX < 77 then
                menustate = "socials"
            end
        elseif mouseY > 32 and mouseY < 43 then
            if mouseX > 15 and mouseX < 32 then
                if theme["themenum"] == 8 then
                    changeTheme(1)
                else
                    changeTheme(theme["themenum"] + 1)
                end
                setTheme()
            elseif mouseX > 47 and mouseX < 64 then
                menustate = "edit"
            end
        elseif mouseY > 48 and mouseX > 30 and mouseX < 50 then
            menustate = "albums"
        end
    elseif menustate=="about" then
        menustate = "settings"
    elseif menustate=="socials" then
        menustate = "settings"
    end
end

local function touchSmallColour(x,y)
    local mouseX, mouseY = x, y
    if mouseX<16 then
        if shuffle==false then
            shuffle = true
        else shuffle = false
        end
        refreshSmallColour()
        if trackplaying~=0 then
            makeQueue(albumplaying)
        end
    elseif mouseX<32 and queuepos then
        playPrevious()
        refreshSmallColour()
    elseif mouseX<48 then
        if audiohandle then
            if playpause==false then
                playpause = true
            else playpause = false
            end
            refreshGrey()
            refreshSmallColour()
        end
    elseif mouseX<64 and queuepos then
        playNext()
        if displayphrase ~= "Error Loading Track" then
            playpause = true
        end
        if loop and queuepos==1 then
            refreshSmallColour()
        end
    elseif mouseX > 64 then
        if loop==false then
            loop = true
        else loop = false
        end
        refreshSmallColour()
    end
end

local function touchSpeaker(x,y)
    local mouseX, mouseY = x, y
    if mouseX > 3 and mouseX < 13 then
        if mouseY > 1 and mouseY < 6 then
            if volume < 3 then
                volume = volume + 0.5
                refreshSpeaker()
            else
                volumeupwobble = true
            end
        elseif mouseY > 18 and mouseY < 24 then
            if volume > 0 then
                volume = volume - 0.5
                refreshSpeaker()
            else
                volumedownwobble = true
            end
        end
    end
end

local function frozenWobble(message)
    bigcolourmonitor.setPaletteColor(colours.red, 0xCC4C4C)
    local function shake(d)
        bigcolourmonitor.clear()
        bigcolourmonitor.setTextColour(colours.red)
        bigcolourmonitor.setBackgroundColour(colours.grey)
        mf.writeOn(bigcolourmonitor, string.rep(" ", 25)..message..string.rep(" ", 25), nil, nil, {scale = 1, dx = d})
        sleep(0.1)
        bigcolourmonitor.setBackgroundColour(colours.black)
    end
    shake(-2)
    shake(2)
    shake(-1)
    shake(1)
    bigcolourmonitor.setTextColour(colours.white)
    bigcolourmonitor.setBackgroundColour(colours.black)
    refreshBigColour()
end

local function arrowWobble()
    while true do
        if (leftarrowwobble==true)then
            bigcolourmonitor.setTextColour(colours.white)
            mf.writeOn(bigcolourmonitor, "< ", 2, 50, {dx = -1, dy = -1, scale = 1})
            sleep(0.1)
            mf.writeOn(bigcolourmonitor, " <", -1, 50, {dx = 1, dy = -1, scale = 1})
            sleep(0.1)
            mf.writeOn(bigcolourmonitor, "< ", 2, 50, {dy = -1, scale = 1})
            leftarrowwobble = false
        elseif (rightarrowwobble==true)then
            bigcolourmonitor.setTextColour(colours.white)
            mf.writeOn(bigcolourmonitor, " >", 73, 50, {dx = 1, dy = -1, scale = 1})
            sleep(0.1)
            mf.writeOn(bigcolourmonitor, "> ", 76, 50, {dx = -1, dy = -1, scale = 1})
            sleep(0.1)
            mf.writeOn(bigcolourmonitor, " >", 73, 50, {dy = -1, scale = 1})
            rightarrowwobble = false
        else
            sleep (0.05)
        end
    end
end

local function displayPhraseMarquee()
    while true do
        if greymarquee then
            for i = 2, 0,-1 do
                if greymarquee then
                    mf.writeOn(greymonitor, string.sub(tempdisplayphrase, 1, 27), i, 2, {scale = 1})
                end
                for j = 2,4,1 do
                    if greymarquee then
                        greymonitor.setCursorPos(1, j)
                        greymonitor.write("  ")
                        greymonitor.setCursorPos(78, j)
                        greymonitor.write("  ")
                    end
                end
                sleep(0.05)
            end
            local temp = string.sub(tempdisplayphrase, 1, 1)
            tempdisplayphrase = string.sub(tempdisplayphrase, 2, #tempdisplayphrase)..temp
        else
            sleep(0.05)
        end
    end
end

local function Marquee()
    while true do
        if albummarquee then
            for i = 2,-3,-1 do
                if albummarquee then
                    mf.writeOn(bigcolourmonitor, string.sub(tempalbumname, 1, 14), i, 2, {scale = 2})
                end
                for j = 2,7,1 do
                    if albummarquee then
                        bigcolourmonitor.setCursorPos(1, j)
                        bigcolourmonitor.write(" ")
                        bigcolourmonitor.setCursorPos(79, j)
                        bigcolourmonitor.write(" ")
                    end
                end
                sleep(0.05)
            end
            local temp = string.sub(tempalbumname, 1, 1)
            tempalbumname = string.sub(tempalbumname, 2, #tempalbumname)..temp
        elseif disklabelmarquee then
            for i = 2,-3,-1 do
                if disklabelmarquee then
                    mf.writeOn(bigcolourmonitor, string.sub(tempdisklabel, 1, 14), i, 2, {scale = 2})
                end
                for j = 2,7,1 do
                    if disklabelmarquee then
                        bigcolourmonitor.setCursorPos(1, j)
                        bigcolourmonitor.write(" ")
                        bigcolourmonitor.setCursorPos(79, j)
                        bigcolourmonitor.write(" ")
                    end
                end
                sleep(0.05)
            end
            local temp = string.sub(tempdisklabel, 1, 1)
            tempdisklabel = string.sub(tempdisklabel, 2, #tempdisklabel)..temp
        else
            sleep(0.05)
        end
    end
end

local function checkEvents()
    repeat
        local event, monitornum, mouseX, mouseY = os.pullEvent()

        if event=="disk" then
            diskCheck()
            refreshBigColour()
            refreshSmallColour()
            refreshGrey()
        elseif event=="disk_eject" then
            diskRemove()
            refreshBigColour()
            refreshSmallColour()
            refreshGrey()
        end

        if event=="monitor_touch" then
            if diskdrive.isDiskPresent() then
                if monitornum==peripheral.getName(smallcolourmonitor) then
                    touchSmallColour(mouseX, mouseY)
                end
                if monitornum==peripheral.getName(bigcolourmonitor) then
                    touchBigColour(mouseX, mouseY)
                    refreshBigColour()
                    refreshSmallColour()
                end
                if monitornum==peripheral.getName(speakermonitor) then
                    touchSpeaker(mouseX, mouseY)
                end
            else
                frozenWobble("No Disk Present")
            end
        end
    until event=="char"
end

local function progressTracker()
    while true do
        if playpause then
            sleep(0.5)
            progress = progress + 0.5
        else
            sleep(0.5)
        end
    end
end

local function progressBarDisplay()
    while true do
        if playpause then
            greymonitor.setTextColour(colours.grey)
            greymonitor.setCursorPos(3, 6)
            greymonitor.write(string.rep("\143", 75))
            greymonitor.setTextColour(colours.lightGrey)
            mf.writeOn(greymonitor, formatTime(progress), 3, 8, {scale = 1})
            greymonitor.setTextColour(colours.white)
            greymonitor.setCursorPos(3, 6)
            greymonitor.write(string.rep("\143", math.floor(75*progress/duration)))
            sleep(1)
        else
            sleep(0.1)
        end
    end
end

local function streamAudio()
    while true do
        if not playpause then
            sleep(0.05)
        else
            local chunk
            if audiohandle then
                chunk = audiohandle.read(1000)
            end
            if not chunk then
                playNext()
            else
                buffer = decoder(chunk)
                while not speaker.playAudio(buffer, volume)do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        end
    end
end

bigcolourmonitor.setBackgroundColour(colours.black)
greymonitor.setBackgroundColour(colours.black)
smallcolourmonitor.setBackgroundColour(colours.black)
speakermonitor.setBackgroundColour(colours.black)
changeTheme()
setTheme()
diskCheck()
refreshBigColour()
refreshGrey()
refreshSmallColour()
refreshSpeaker()

parallel.waitForAny(checkEvents, Marquee, arrowWobble, progressTracker, streamAudio, displayPhraseMarquee, progressBarDisplay)






