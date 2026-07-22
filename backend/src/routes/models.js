const express = require('express');
const { listModels } = require('../utils/modelCatalog');

const router = express.Router();

router.get('/', (req, res) => {
  res.json({ models: listModels() });
});

module.exports = router;
