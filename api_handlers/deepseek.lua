local BaseHandler = require("api_handlers.base")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")

local DeepSeekHandler = BaseHandler:new()

function DeepSeekHandler:query(message_history, config)
    local deepseek_settings = config.provider_settings and config.provider_settings.deepseek

    if not deepseek_settings or not deepseek_settings.api_key then
        return "Error: Missing API key in configuration"
    end

    -- DeepSeek uses OpenAI-compatible API format
    local requestBodyTable = {
        model = deepseek_settings.model,
        messages = message_history,
        max_tokens = (deepseek_settings.additional_parameters and deepseek_settings.additional_parameters.max_tokens)
    }

    local requestBody = json.encode(requestBodyTable)
    local responseBody = {}
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. deepseek_settings.api_key
    }

    local success, code = https.request({
        url = deepseek_settings.base_url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(requestBody),
        sink = ltn12.sink.table(responseBody)
    })

    if not success then
        return "Error: Failed to connect to DeepSeek API - " .. tostring(code)
    end

    local response = json.decode(table.concat(responseBody))
    
    if response and response.choices and response.choices[1] and response.choices[1].message then
        return response.choices[1].message.content
    else
        return "Error: Unexpected response format from API: " .. table.concat(responseBody)
    end
end

return DeepSeekHandler 