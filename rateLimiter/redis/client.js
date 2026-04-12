const Redis = require('ioredis');

const client = new Redis({
    host: "localhost",
    port: 6379
})

module.exports = client