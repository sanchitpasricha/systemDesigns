local key = KEYS[1];
local queue_capacity = tonumber(ARGV[1]);
local leak_rate = tonumber(ARGV[2]);
local now = tonumber(ARGV[3]);

local data = redis.call('HMGET', key, 'tokens', 'last_leak_time');
local tokens = tonumber(data[1]) or 0;
local last_leak_time = tonumber(data[2]) or now

local leaked = leak_rate * (now - last_leak_time);
local current_queue = math.max(0, tokens - leaked)

if current_queue < queue_capacity then
  current_queue = current_queue + 1;                                                                                                                
  redis.call('HMSET', key, 'tokens', current_queue, 'last_leak_time', now)
  return 1                                                                                                                      
else
    return 0;
end 