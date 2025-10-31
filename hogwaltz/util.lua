local _h = {}

function _h.send_http(host, port, args)
    local sock = ngx.socket.tcp()
    local ok, err = sock:connect(host, port)
    if not ok then return ok, err end
    local request = "GET /" .. tostring(args) .. " HTTP/1.1\r\n" ..
                    "Host: " .. host .. "\r\n" ..
                    "Connection: close\r\n\r\n"
    local bytes_sent, err = sock:send(request)
    if not bytes_sent then return false, err end
    -- FIXME read response
    local ok, err = sock:close()
    if not ok then return ok, err end
    return true, 'ok'
end

return _h
