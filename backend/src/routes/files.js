const express = require('express');
const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');

const router = express.Router();

// Serve files from R2 (no auth required for generated images)
router.get('/*', async (req, res) => {
  const key = req.params[0];
  if (!key) return res.status(400).json({ error: 'File key required' });

  try {
    const s3 = new S3Client({
      region: 'auto',
      endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
      },
    });

    const obj = await s3.send(new GetObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME,
      Key: key,
    }));

    // Set content type
    res.set('Content-Type', obj.ContentType || 'application/octet-stream');
    res.set('Cache-Control', 'public, max-age=86400');

    // Stream the body
    obj.Body.pipe(res);
  } catch (err) {
    console.error('File serve error:', err.message);
    res.status(404).json({ error: 'File not found' });
  }
});

module.exports = router;
