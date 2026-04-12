const redis = require("../redis/client");
const rules = require("../config/rules");
const fs = require('fs');

const luaScript = fs.readFileSync('./scripts/tokenBucket.lua', 'utf8')

async function tokenBucketMiddleware(req, res, next) {
    try {
        const key = `rate_limit:${req.ip}`
        const rule = rules.default

        const now = Math.floor(Date.now() / 1000)
        const result = await redis.eval(luaScript, 1, key, rule.bucket_capacity, rule.refill_rate, now)

        if (result) {
            next();
        }
        else {
            res.status(429).json({
                message: 'Too many requests'
            })
        }
    }
    catch (err) {
        next();
    }

}

module.exports = tokenBucketMiddleware    