local BaseHandler = require("api_handlers.base")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")

local OpenRouterProvider = BaseHandler:new()

function OpenRouterProvider:query(message_history, config)
    local openrouter_settings = config.provider_settings and config.provider_settings.openrouter
    
    local requestBodyTable = {
        model = openrouter_settings.model,
        messages = message_history,
        max_tokens = openrouter_settings.max_tokens,
        temperature = openrouter_settings.temperature
    }

    local requestBody = json.encode(requestBodyTable)
    local responseBody = {}
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. (openrouter_settings.api_key or config.api_key),
        ["HTTP-Referer"] = "https://github.com/omer-faruq/assistant.koplugin",
        ["X-Title"] = "assistant.koplugin"
    }

    local response = {}
    local status, code, responseHeaders = https.request{
        url = openrouter_settings.base_url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(requestBody),
        sink = ltn12.sink.table(response),
        protocol = "tlsv1_2"
    }

    if status and code == 200 then
        local responseData = json.decode(table.concat(response))
        if responseData and responseData.choices and responseData.choices[1] then
            return responseData.choices[1].message.content
        end
    end
    
    return nil, "Error: " .. (code or "unknown") .. " - " .. table.concat(response)
end

return OpenRouterProvider
