local M = {}

---@param mime string
---@param url string
---@param content string[]
local function open_mime(content, url, mime)
    local filetype = M.mimetype_lookup[mime]
    if not vim.startswith(mime, "text/") then
        vim.ui.select({
            "Open in external program",
            "Open anyway"
        }, {
            prompt = "Non text content"
        }, function(choice)
            if choice == nil then
                return
            elseif choice == "Open in external program" then
                local tmp = vim.fn.tempname()
                local f = io.open(tmp, "w")

                if f == nil then
                    return
                end

                f:write(table.concat(content, "\n"))
                f:close()

                vim.ui.open(tmp)
            elseif choice == "Open anyway" then
                if filetype == nil then
                    filetype = "text"
                end
                M.openwindow(content, url, filetype)
            end
        end)
        return
    end
    if filetype == nil then
        filetype = "text"
    end
    M.openwindow(content, url, filetype)
end

function M.submitinput(url, response)
    if response == "" or response == nil then
        return
    end

    local query = vim.uri_encode(response)
    M.openurl(url .. "?" .. query)
end

---@param url string
---@param prompt string
local function input(url, prompt)
    local buf = vim.api.nvim_create_buf(false, false)

    vim.bo[buf].buftype = "acwrite"

    vim.api.nvim_buf_set_name(buf, "[GEMINI PROMPT]")

    local w = vim.o.columns
    local h = vim.o.lines
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = w - 20,
        height = h - 7,
        col = 10,
        row = 3,
        style = "minimal",
        border = "rounded",
        title = prompt
    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {
        once = true,
        buffer = buf,
        callback = function()
            local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
            vim.api.nvim_win_close(win, true)
            vim.api.nvim_buf_delete(buf, {
                force = true
            })
            M.submitinput(url, text)
        end
    })
end

---@param url string
---@param prompt string
local function input_secret(url, prompt)
    local resp = vim.fn.inputsecret(prompt .. "> ")
    M.submitinput(url, resp)
end

local config = {
    certificates = {},
    open_mime = open_mime,
    input = input,
    input_secret = input_secret,
}

M.mimetype_lookup = {
    ["text/gemini"] = "gemtext",
    ["text/html"] = "html",
    ["text/markdown"] = "markdown",
}

---@param mimetype string
---@param filetype string
function M.addmime(mimetype, filetype)
    M.mimetype_lookup[mimetype] = filetype
end

M.status = {
    INPUT = 10,
    SUCCESS = 20,
    REDIRECT = 30,
    TEMP_FAILURE = 40,
    PERMANENT_FAILURE = 50,
    CLIENT_CERTIFICATE = 60
}

---@param baseURL string
---@param currentURL string
---@param newURL string
local function joinPath(baseURL, currentURL, newURL)
    if vim.startswith(newURL, "/") then
        return baseURL .. newURL
    elseif string.find(newURL, "://") then
        return newURL
    elseif vim.startswith(newURL, "?") then
        return currentURL .. newURL
    elseif vim.startswith(newURL, ".") then
        return currentURL .. vim.fn.slice(newURL, 1)
    else
        local base = vim.fs.dirname(currentURL)
        if not vim.endswith(currentURL, "/") then
            return base .. "/" .. newURL
        end
        return currentURL .. newURL
    end
end

local function setup()
    vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "gemini://*",
        callback = function()
            if not vim.startswith(vim.api.nvim_buf_get_name(0), "gemini://") then
                return
            end

            vim.keymap.set("n", "gf", function()
                local path = vim.fn.expand("<cWORD>")
                local bufName = vim.api.nvim_buf_get_name(0)
                local base = vim.iter(string.gmatch(bufName, "gemini://[^/]*")):totable()[1]
                local newPath = joinPath(base, bufName, path)
                vim.cmd.edit(newPath)
            end)
            local name = vim.api.nvim_buf_get_name(0)

            M.openurl(name)

            vim.bo.modified = false
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
        end
    })
end

function M.setup(user_conf)
    config = vim.tbl_extend("force", config, user_conf)

    setup()
end

---@param number number
local function number2status(number)
    if number < 10 or number > 69 then
        return false
    end

    number = vim.fn.floor(number / 10) * 10

    if number == 10 then
        return M.status.INPUT
    elseif number == 20 then
        return M.status.SUCCESS
    elseif number == 30 then
        return M.status.REDIRECT
    elseif number == 40 then
        return M.status.TEMP_FAILURE
    elseif number == 50 then
        return M.status.PERMANENT_FAILURE
    elseif number == 60 then
        return M.status.CLIENT_CERTIFICATE
    end
end

function M.request(url)
    local args = { "gmni", "-i" }

    local domain = vim.split(url, "/")[3]

    local certFile, keyFile
    if config.certificates[domain] ~= nil then
        local files = config.certificates[domain]
        certFile = vim.fn.expand(files.cert)
        keyFile = vim.fn.expand(files.key)
    end

    --Both must be set, otherwise neither are set
    if certFile == nil or keyFile == nil then
        certFile = nil
        keyFile = nil
    end

    if certFile ~= nil then
        args[#args + 1] = "-E"
        args[#args + 1] = certFile .. ":" .. keyFile
    end

    args[#args + 1] = url

    local result = vim.system(args):wait()

    if result.code == 1 then
        vim.print("Invalid url")
        return false
    end

    if result.code == 6 then
        vim.print("A certificate for '" .. url .. "' was not found")
        local trusts = vim.fn.input("Trust? [y/N]: ")

        if trusts ~= "y" then
            return false
        end
        result = vim.system({ "gmni", "-j", "always", "-i", url }):wait()
    end

    local header = vim.split(result.stdout, "\n", { plain = true })[1]
    local text = vim.fn.slice(vim.split(result.stdout, "\n", { plain = true }), 1)

    local sep = string.find(header, " ")

    local statusNr, info = ""
    if sep == nil then
        ---@type number
        statusNr = tonumber(header)
    else
        ---@type number
        statusNr = tonumber(vim.fn.slice(header, 0, sep - 1))
        info = vim.fn.slice(header, sep)
    end

    local statusCode = number2status(statusNr)

    if statusCode == false then
        vim.notify(
            "An invalid status was given, continuing as status 20",
            vim.log.levels.WARN
        )
    end

    return text, statusNr, info
end

---@param url string
function M.openurl(url)
    local text, statusNr, info = M.request(url)

    if text == false then
        return
    end

    local status = number2status(statusNr)

    if status == M.status.SUCCESS then
        local filedata = vim.fn.split(info, ";")
        local mime = filedata[1]
        config.open_mime(text, url, mime)
    elseif status == M.status.REDIRECT then
        M.openurl(info)
    elseif status == M.status.INPUT then
        local isSensitive = statusNr == 11
        if isSensitive then
            config.input_secret(url, info)
        else
            config.input(url, info)
        end
    elseif status == M.status.TEMP_FAILURE then
        local texts = {
            [41] = "This server is currently unavailble due to overload or maintenance",
            [42] = "A CGI or similar system for generating dynamic content failed",
            [43] =
            "A proxy request failed because the server was unable to successfully complete a transaction with the remote host",
            [44] = "Too many requests"
        }
        local errtext = texts[statusNr]
        if errtext == nil then
            errtext = "An error occured got: " .. tostring(statusNr)
        end
        vim.cmd.echohl("Error")
        vim.print(text)
        vim.cmd.echohl("None")
    elseif status == M.status.PERMANENT_FAILURE then
        local texts = {
            [51] = "Not found",
            [52] = "Gone",
            [53] = "Proxy request refused",
            [59] = "Bad request"
        }
        local errtext = texts[statusNr]
        if errtext == nil then
            errtext = "An error occured got: " .. tostring(statusNr)
        end
        vim.cmd.echohl("Error")
        vim.print(errtext)
        vim.cmd.echohl("None")
    elseif status == M.status.CLIENT_CERTIFICATE then
        vim.notify("Client certificate errors are not implemented", vim.log.levels.ERROR)
    end
end

---@param text string[]
---@param url string
---@param filetype string
---@return number, number
function M.openwindow(text, url, filetype)
    -- local buf = vim.api.nvim_create_buf(true, false)
    --
    -- vim.api.nvim_open_win(buf, true, {
    --     split = 'left'
    -- })
    --
    -- vim.api.nvim_buf_set_lines(buf, 0, 0, false, text)
    -- vim.bo[buf].filetype = filetype

    vim.api.nvim_buf_set_name(0, url)
    vim.api.nvim_buf_set_lines(0, 0, 0, false, text)
    vim.bo.filetype = filetype
    vim.bo.modified = false

    -- return win, buf
end

return M
