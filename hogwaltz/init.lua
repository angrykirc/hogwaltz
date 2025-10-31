-- prepare configuration, should be self explanational
ngx.shared.hogwaltz.config = {
    cookie_name = 'hogwaltz', -- challenge cookie name
    memcached_shards = { -- hostname:port list of memcached servers
        {'127.0.0.1', '11211'}
    },
    memcached_pool_timeout = 10000, -- timeout for memcached keepalive pool (ms)
    memcached_pool_size = 20, -- size limit for memcached keepalive pool
    memcached_timeout = 250, -- timeout for memcached operations (ms)
    memcached_prefix_challenge = 'ch_', -- prefix for challenges
    memcached_prefix_tries = 'tr_', -- prefix for retries
    memcached_prefix_metric = 'mt_', -- prefix for metrics (per-shard)
    challenge_lifetime = 3600, -- lifetime of successfull challenge
    tries_lifetime = 600, -- lifetime of failed challenge count
    tries_allowed = 3, -- allowed retries in case of failed challenge
    challenge_salt = 'absolutecinema', -- salt hash for challenge (so it won't be precomputed)
    challenge_hardness = 999999, -- difficulty of challenge, default is pretty balanced
    fail_open = true, -- in case of error pass through 
    log_chance = 100, -- 1000 means log 100% of requests
    whitelist_nets = { -- whitelisted networks
        --'127.0.0.1/32'
    },
    report_host = '127.0.0.1', -- API url to send bans to, HTTP only, can be nil = disabled
    report_port = 8080, -- API port for bans api
    report_text = '?ip=BADGUYIP' -- HTTP arguments for bans api
}

