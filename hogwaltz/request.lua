local hogwaltz = require "hogwaltz"
local ipmatcher = require "resty.ipmatcher"

-- main request pipeline start
local hog = hogwaltz.new()
hog:log_text('got request')

-- store things from nginx
local client_ip = ngx.var.remote_addr
local client_ch = ngx.var['cookie_' .. hog.conf.cookie_name]

-- test against whitelisted networks
ipmatcher = ipmatcher.new(hog.conf.whitelist_nets)
-- pass-through if matches
if ipmatcher:match(client_ip) then 
    hog:log_text('bypass due to whitelist')
    return 
end

-- if not whitelisted, go on
local shard = hog:find_shard(client_ip)
if shard == nil then return end -- in case parsing fails
if hog:open_memcached(shard) == nil then return end -- in case connection fails
hog:log_text('assigned shard ' .. shard)
-- try to fetch challenge from memcached
local stored_ch = hog:get_challenge(client_ip)

-- state machine begins here
-- check if challenge was already issued or not
if stored_ch == nil then
    -- generate a new challenge and store it to memcached
    local ch = hog:set_challenge(client_ip)
    if ch == nil then return end -- memcached failure or something else
    hog:log_text('sending challenge ' .. ch)
    hog:incr_metric('sent')
    hog:close_memcached()
    -- replace response with a challenge page
    return hog:send_challenge(client_ip, ch)
else
    -- challenge was issued, check cookie
    hog:log_text('got challenge response ' .. tostring(client_ch))
    if client_ch == stored_ch then
        -- everything is OK, pass through
        hog:log_text('challenge OK!')
        hog:incr_metric('pass')
    else
        -- incorrect response is found in cookie (or nil = no cookie)
        hog:log_text('challenge failed!')
        local tr = hog:get_tries(client_ip)
        if tr == nil then return end -- memcached failure or something else
        -- show challenge page a few times again
        if tr < hog.conf.tries_allowed then
            hog:log_text('re-sending challenge until retry limit')
            hog:incr_tries(client_ip, tr)
            hog:incr_metric('fail')
            hog:close_memcached()
            return hog:send_challenge(client_ip, stored_ch)
        else
            hog:log_text('send reset/ban due to exceeded retries')
            hog:incr_metric('bans')
            hog:close_memcached()
            return hog:hard_ban(client_ip)
        end
    end
end

hog:close_memcached()
