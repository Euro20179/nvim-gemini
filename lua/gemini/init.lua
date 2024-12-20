local M = {}

local config = {
    ---@param mime string
    ---@param url string
    ---@param content string[]
    open_mime = function(content, url, mime)
        local filetype = M.mimetype_lookup[mime]
        if filetype == nil then
            filetype = "text"
        end
        M.openwindow(content, url, filetype)
    end
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
    else
        return currentURL .. '/' .. newURL
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
            vim.cmd.norm("gg")
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
    local result = vim.system({ "gmni", "-i", url }):wait()

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

    local header = vim.fn.split(result.stdout, "\n")[1]
    local text = vim.fn.slice(vim.fn.split(result.stdout, "\n"), 1)

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

    vim.api.nvim_buf_set_lines(0, 0, 0, false, text)
    vim.bo.filetype = filetype

    -- return win, buf
end

return M
