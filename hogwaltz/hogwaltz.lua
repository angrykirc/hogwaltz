local _h = {}
_h.__index = _h
-- requires are cached per nginx worker
local resty_random = require "resty.random"
local resty_memcached = require "resty.memcached"
local resty_ipmatcher = require "resty.ipmatcher"
local errlog = require "ngx.errlog"
local challenge = require "challenge"
local util = require "util"

-- instantiate new request pipeline; heap is bad I know
function _h.new()
    local self = setmetatable({}, _h)
    self.conf = ngx.shared.hogwaltz.config
    self.memc = nil
    self.do_log = resty_random.number(0, 1000) > 1000 - self.conf.log_chance
    return self
end

-- logging helper
function _h:log_text(text)
    if self.do_log then
        errlog.raw_log(ngx.NOTICE, '[hog] ' .. text)
    end
end

-- block/ban function
function _h:hard_ban(ip)
    if self.conf.report_host ~= nil then
        local str = ngx.re.gsub(self.conf.report_text, "BADGUYIP", ip)
        local ok, err = util.send_http(self.conf.report_host, self.conf.report_port, str)
        if not ok then self:log_text('failed to send ban report due to ' .. err) end
    end
    return ngx.exit(444)
end

-- fail helper - always terminate or return nil (if fail_open is set)
function _h:fail(from, text)
    self:log_text(from .. ": " .. text)
    if not self.conf.fail_open then
        return ngx.exit(444)
    end
    return nil
end

-- calculate shard number from source IP
function _h:find_shard(ip)
    local v = resty_ipmatcher.parse_ipv4(ip)
    local c = #self.conf.memcached_shards
    if c <= 0 then c = 1 end
    if not v then
        return self:fail('find_shard', 'failed to parse src ip')
    end
    return (v % c) + 1
end

-- calculate hashed salt from source IP and static salt
function _h:get_challenge_salt(ip)
    return ngx.md5(ip .. self.conf.challenge_salt)
end

-- generate challenge (static salt and random number)
function _h:generate_challenge(ip)
    return self:get_challenge_salt(ip) .. resty_random.number(0, self.conf.challenge_hardness)
end

-- calculate and send challenge page to client
function _h:send_challenge(ip, ch)
    ngx.header.content_type = "text/html";
    ngx.status = 200
    ngx.say(challenge.template(
        self:get_challenge_salt(ip), 
        ngx.md5(ch), 
        self.conf.challenge_hardness, 
        self.conf.cookie_name))
    return ngx.exit(ngx.HTTP_OK)
end

-- fetch stored challenge from memcached
function _h:get_challenge(ip)
    if self.memc == nil then
        return self:fail('get_challenge', 'memcached instance is nil')
    end
    local res, flags, err = self.memc:get(self.conf.memcached_prefix_challenge .. ip)
    if err then
        return self:fail('get_challenge', err)
    end
    return res
end

-- store challenge to memcached
function _h:set_challenge(ip)
    if self.memc == nil then
        return self:fail('set_challenge', 'memcached instance is nil')
    end
    local ch = self:generate_challenge(ip)
    local ok, err = self.memc:set(self.conf.memcached_prefix_challenge .. ip, ch, self.conf.challenge_lifetime)
    if not ok then
        return self:fail('set_challenge', err)
    end
    return ch
end

-- increase metric by 1
function _h:incr_metric(metric)
    if self.memc == nil then
        return self:fail('incr_metric', 'memcached instance is nil')
    end
    local ok, err = self.memc:incr(self.conf.memcached_prefix_metric .. metric, 1)
    if not ok then
        if tostring(err) == 'NOT_FOUND' then
            self.memc:set(self.conf.memcached_prefix_metric .. metric, 1, self.conf.tries_lifetime)
        else
            return self:fail('incr_metric', err)
        end
    end
    return true
end

-- store tries count to memcached
function _h:incr_tries(ip)
    if self.memc == nil then
        return self:fail('set_tries', 'memcached instance is nil')
    end
    local ok, err = self.memc:incr(self.conf.memcached_prefix_tries .. ip, 1)
    if not ok then
        if tostring(err) == 'NOT_FOUND' then
            self.memc:set(self.conf.memcached_prefix_tries .. ip, 1, self.conf.tries_lifetime)
        else
            return self:fail('set_tries', err)
        end
    end
    return true
end

-- get tries count from memcached
function _h:get_tries(ip)
    if self.memc == nil then
        return self:fail('get_tries', 'memcached instance is nil')
    end
    local res, flags, err = self.memc:get(self.conf.memcached_prefix_tries .. ip)
    if err then
        return self:fail('get_tries', err)
    end
    if res == nil then return 0 end
    return tonumber(res)
end

-- open memcached connection by shard id
function _h:open_memcached(shard_id)
    local shard_data = self.conf.memcached_shards[shard_id]
    if not shard_data then
        return self:fail('open_memcached', 'missing shard for memcached')
    end
    local memhost = shard_data[1] -- lua index starts at 1
    local memport = shard_data[2]
    local memc, err = resty_memcached:new()
    if not memc then
        return self:fail('open_memcached', err)
    end
    memc:set_timeout(self.conf.memcached_timeout)
    local ok, err = memc:connect(memhost, memport)
    if not ok then
        return self:fail('open_memcached', err)
    end
    self.memc = memc
    return true
end

-- close/return memcached connection to pool
function _h:close_memcached()
    if self.memc == nil then 
        return self:fail('close_memcached', 'memcached not instantiated')
    end
    local ok, err = self.memc:set_keepalive(self.conf.memcached_pool_timeout, self.conf.memcached_pool_size)
    if not ok then
        return self:fail('close_memcached', err)
    end
end

return _h
