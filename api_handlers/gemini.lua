local BaseHandler = require("api_handlers.base")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")

local GeminiHandler = BaseHandler:new()

function GeminiHandler:query(message_history, config)    
    local gemini_settings = config.provider_settings and config.provider_settings.gemini
    
    if not gemini_settings or not gemini_settings.api_key then
        return "Error: Missing API key in configuration"
    end

    -- Gemini API requires messages with explicit roles
    local contents = {}
    local systemMessage = nil

    for i, msg in ipairs(message_history) do
        -- First message is treated as system message
        if i == 1 and msg.role ~= "user" then
            systemMessage = {
                role = "user",
                parts = {{ text = msg.content }}
            }
        else
            table.insert(contents, {
                role = "user",
                parts = {{ text = msg.content }}
            })
        end
    end

    -- If a system message exists, insert it at the beginning
    if systemMessage then
        table.insert(contents, 1, systemMessage)
    end

    local requestBodyTable = {
        contents = contents,
        safety_settings = {
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
        }
    }

    local requestBody = json.encode(requestBodyTable)
    
    local responseBody = {}
    local headers = {
        ["Content-Type"] = "application/json"
    }

    local model = gemini_settings.model
    local base_url = gemini_settings.base_url

    local success, code, responseHeaders = https.request({
        url = string.format("%s%s:generateContent?key=%s", base_url, model, gemini_settings.api_key),
        method = "POST",
        headers = headers,
        source = ltn12.source.string(requestBody),
        sink = ltn12.sink.table(responseBody)
    })

    if not success then
        return "Error: Failed to connect to Gemini API - " .. tostring(code)
    end

    local responseText = table.concat(responseBody)

    local success, response = pcall(json.decode, responseText)
    
    if not success then
        print("JSON Decode Error: " .. tostring(response))
        return "Error: Failed to parse Gemini API response - " .. tostring(response)
    end
    
    if response and response.candidates and response.candidates[1] and 
       response.candidates[1].content and response.candidates[1].content.parts and
       response.candidates[1].content.parts[1] then
        return response.candidates[1].content.parts[1].text
    else
        return "Error: Unexpected response format from Gemini API: " .. table.concat(responseBody)
    end
end

return GeminiHandler