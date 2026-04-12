local key = KEYS[1]                                                                                                                   
local bucket_capacity = tonumber(ARGV[1])                                                                                             
local refill_rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])                                                                                                         

-- Read current state from Redis
local data = redis.call('HMGET', key, 'tokens', 'last_refill_time')                                                                   
local tokens = tonumber(data[1]) or bucket_capacity                                                                                   
local last_refill_time = tonumber(data[2]) or now
                                                                                                                                      
-- Calculate refill                                                                                                                   
local elapsed = now - last_refill_time
local tokens_to_add = elapsed * refill_rate                                                                                           
tokens = math.min(bucket_capacity, tokens + tokens_to_add)

-- Allow or reject                                                                                                                    
if tokens >= 1 then
  tokens = tokens - 1                                                                                                                 
  redis.call('HMSET', key, 'tokens', tokens, 'last_refill_time', now)
  return 1
else                                                                                                                                  
  redis.call('HMSET', key, 'last_refill_time', now)
  return 0                                                                                                                            
end 