local _h = {}
_h.__index = _h
-- requires are cached per nginx worker
local resty_memcached = require "resty.memcached"
local errlog = require "ngx.errlog"
local ngx_re = require "ngx.re"
local metric_names = {'sent', 'pass', 'fail', 'bans'}
local memc_metrics = {'max_connections', 'curr_connections', 'bytes', 'limit_maxbytes', 'curr_items', 'listen_disabled_num'}

function _h.new()
    local self = setmetatable({}, _h)
    self.conf = ngx.shared.hogwaltz.config
    self.memc = nil
    return self
end

function _h:fail(where, text)
    errlog.raw_log(ngx.NOTICE, '[' .. where .. ']' .. text)
    return nil
end

-- get tries count from memcached
function _h:get_metric(metric)
    if self.memc == nil then
        return self:fail('get_metric', 'memcached instance is nil')
    end
    local res, flags, err = self.memc:get(self.conf.memcached_prefix_metric .. metric)
    if err then
        return self:fail('get_metric', err)
    end
    if res == nil then return 0 end
    return tonumber(res)
end

-- get stats form memcached
function _h:get_stats()
    if self.memc == nil then
        return self:fail('get_stats', 'memcached instance is nil')
    end
    local lines, err = self.memc:stats()
    if err then
        return self:fail('get_stats', err)
    end
    -- convert to name:value dict
    local nstats = {}
    for _, v in ipairs(lines) do
        v = ngx_re.split(v, ' ')
        nstats[v[2]] = v[3]
    end
    return nstats
end

-- send metrics as nginx response
function _h:send_metrics()
    local shardstatus = {}
    local shardmetric = {}

    for k, v in ipairs(self.conf.memcached_shards) do
        local rk = v[1] .. ':' .. v[2]
        shardstatus[rk] = {}
        shardmetric[rk] = {}

        if self:open_memcached(k) == nil then
            shardstatus[rk]['online'] = 0
        else 
            shardstatus[rk]['online'] = 1
            -- collect and parse memcached metrics
            shardstatus[rk]['stats'] = self:get_stats()
            -- collect and parse app metrics
            for _, v in ipairs(metric_names) do
                shardmetric[rk][v] = self:get_metric(v)
            end
            self:close_memcached()
        end
    end

    local resp = ''
    
    for s, d in pairs(shardstatus) do
        resp = resp .. '# TYPE memcached_online gauge' .. '\n'
        resp = resp .. 'memcached_online{shard="' .. s .. '"} ' .. tostring(d['online']) .. '\n'
    end

    for _, mname in ipairs(memc_metrics) do
        resp = resp .. '# TYPE memcached_' .. mname .. ' gauge' .. '\n'
        for s, d in pairs(shardstatus) do
            local t = d['stats'][mname]
            if t ~= nil then
                resp = resp .. 'memcached_' .. mname .. '{shard="' .. s .. '"} ' .. t .. '\n'
            end
        end
    end

    for _, v in ipairs(metric_names) do
        resp = resp .. '# TYPE hog_' .. v .. ' counter' .. '\n'
        for s, d in pairs(shardmetric) do
            resp = resp .. 'hog_' .. v .. '{shard="' .. s .. '"} ' .. tostring(d[v]) .. '\n'
        end
    end
    ngx.status = 200
    ngx.say(resp)
    ngx.exit(ngx.HTTP_OK)
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
    --local ok, err = self.memc:close()
    local ok, err = self.memc:set_keepalive(self.conf.memcached_pool_timeout, self.conf.memcached_pool_size)
    if not ok then
        return self:fail('close_memcached', err)
    end
end

return _h
