term.clear()
shell.run("wget run https://pinestore.cc/d/37")

local repository = "https://raw.githubusercontent.com/Bluerella/ComputerCraft-Blockman/main/"
local paths = {"Blockman.lua", "Icons/about.bimg", "Icons/addmusic.bimg", "Icons/discord.bimg", "Icons/edit.bimg", "Icons/loopOFF.bimg",
"Icons/loopON.bimg", "Icons/minus.bimg", "Icons/pause.bimg", "Icons/play.bimg", "Icons/plus.bimg", "Icons/rewind.bimg", "Icons/shuffleOFF.bimg",
"Icons/shuffleON.bimg", "Icons/skip.bimg", "Icons/themes.bimg"}

local function message(text, x, y)
    term.setTextColour(colours.purple)
    term.setBackgroundColor(colours.black)
    term.setCursorPos(x, y)
    term.clearLine()
    write(text)
end

local function download(path, attempt)
    message("Downloading "..path, 1, 3)
    local handle = http.get(repository..path)
    if not handle then
        if attempt==3 then
            message("Failed to download "..path.." after 3 attempts", 1, 3)
            message("Installation may be corrupt, please try again", 1, 1)
        else
            message("Failed to download "..path..", trying again")
            return download(path, attempt+1)
        end
    else
        local data = handle.readAll()
        local file = fs.open(path, "w")
        file.write(data)
        file.close()
        message("Downloaded "..path, 1, 5)
    end
end

local function install()
    message("Installing...", 1, 1)
    for i=1, #paths do
        download(paths[i], 1)
    end
    message("Installation complete", 1, 5)
end

install()

sleep(1)

term.setBackgroundColor(colours.black)
term.setTextColor(colours.white)
term.setCursorPos(1, 1)
term.clear()
