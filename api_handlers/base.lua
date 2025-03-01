local BaseHandler = {}

function BaseHandler:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function BaseHandler:query(message_history)
    -- To be implemented by specific handlers
    error("query method must be implemented")
end

return BaseHandler 