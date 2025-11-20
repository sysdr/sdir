import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const app = express();
app.use(express.static(join(__dirname, 'public')));

app.listen(3000, () => {
  console.log('Dashboard running on http://localhost:3000');
});
