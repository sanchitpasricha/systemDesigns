const express = require('express')
const tokenBucket = require('./middleware/tokenBucket');

const app = express();

app.use(tokenBucket);
app.get('/', (req,res) => {
    res.json({
        message: 'OK'
    })
})

app.listen(3000, () => {
    console.log('Server running on 3000');
})
