const express = require('express');
const path = require('path');
const app = express();

app.use(express.static('public'));

app.listen(8080, () => {
  console.log('Frontend Dashboard running on http://localhost:8080');
});
