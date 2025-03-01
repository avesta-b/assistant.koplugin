local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
local meta = require("_meta")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")

local function checkForUpdates()
  local response_body = {}
  local _, code = http.request {
    url = "https://api.github.com/repos/omer-faruq/assistant.koplugin/releases/latest",
    headers = {
        ["Accept"] = "application/vnd.github.v3+json"
    },
    sink = ltn12.sink.table(response_body)
  }

  if code == 200 then
    local data = table.concat(response_body)
    local parsed_data = json.decode(data)
    local latest_version = parsed_data.tag_name -- e.g., "v0.9"
    
    -- Safe version comparison
    if latest_version then
      local stripped_latest_version = latest_version:match("^v(.+)$")
      if stripped_latest_version then
        local latest_number = tonumber(stripped_latest_version)
        if latest_number and meta.version and latest_number > meta.version then
          -- Show notification to the user if a new version is available
          local message = "A new version of the " .. meta.fullname .. " plugin (" .. latest_version .. ") is available. Please update!"
          local info_message = InfoMessage:new{
              text = message,
              timeout = 5 -- Display message for 5 seconds
          }
          UIManager:show(info_message)
        end
      end
    end
  else
    print("Failed to check for updates. HTTP code:", code)
  end
end

return {
  checkForUpdates = checkForUpdates
}