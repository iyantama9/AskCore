const express = require('express');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { isPublicKey, normalizeR2Key } = require('../utils/files');
const { sendError } = require('../utils/errors');

const router = express.Router();

const s3 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

// Serve public generated images/screenshots only.
router.get('/*', async (req, res) => {
  const key = normalizeR2Key(req.params[0]);
  if (!key) return sendError(res, req, 400, 'File key required', null, 'FILE_KEY_REQUIRED');

  if (!isPublicKey(key)) {
    return sendError(res, req, 404, 'File not found');
  }

  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME,
      Key: key,
    }));

    res.set('Content-Type', obj.ContentType || 'application/octet-stream');
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Cache-Control', 'public, max-age=86400');
    obj.Body.pipe(res);
  } catch (err) {
    return sendError(res, req, 404, 'File not found', err);
  }
});

module.exports = router;
