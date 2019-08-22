-- This basic Lua script attempts to build up a list of relevant requests grouped by
-- a specific key. If the number of requests allowed by 'rate' is reached, it will
-- check to see whether it's within the relevant window. If so, the number of seconds
-- until the limitation is revoked will be returned.

-- set up our basic inputs
local identifier = ARGV[1]
local window = tonumber(ARGV[2])
local rate = tonumber(ARGV[3])
local now = tonumber(ARGV[4])
local limit_key = identifier .. '_limit'

-- Check whether this key is already limited
-- If currently limited, return the amount of time until the limit is lifted
-- This is used as both a shortcut response and a guard to avoid users retrying the 
-- system while restricted from being endlessly rate limited
if redis.call('EXISTS', limit_key) > 0 then
  return redis.call('TTL', limit_key)
end

-- Add the current timestamp to the list
redis.call('LPUSH', identifier, now)

-- Set this list to expire outside the window if no more requests are made
redis.call('EXPIRE', identifier, window)

-- If we don't have enough records yet, there's no need to check whether we're rate
-- limiting this request
if redis.call('LLEN', identifier) <= rate then
  return nil
end

-- Check whether they've exceeded the limit based on the furthest valid timestamp prior
-- to this call
local oldest = redis.call('LINDEX', identifier, rate)

-- Trim the list to the relevant size to ensure we're not storing more than is required
-- We know at this point that these items outside of the rate range are irrelevant, as 
-- they would have otherwise been rate limited 
redis.call('LTRIM', identifier, 0, rate - 1)

-- Calculate the point in time where the entry would be old enough we could discard it
local valid_timeframe = oldest + window

-- If the point of time is in the future, we need to limit this request
if valid_timeframe > now then
  -- Set a key which will limit further requests
  redis.call('SET', limit_key, 1)

  -- Calculate the number of seconds until the limit is revoked
  local revoke_limit_timeframe = valid_timeframe - now

  -- Set the limit key to expire when the limit is revoked
  redis.call('EXPIRE', limit_key, revoke_limit_timeframe)

  return revoke_limit_timeframe
end