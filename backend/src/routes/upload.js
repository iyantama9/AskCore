const express = require('express');
const multer = require('multer');
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { v4: uuidv4 } = require('uuid');
const authMiddleware = require('../middleware/auth');
const { recordFile, assertCanReadR2Key } = require('../utils/files');
const { sendError } = require('../utils/errors');
const { assertQuota, recordUsage } = require('../utils/usage');
const metrics = require('../utils/metrics');

const router = express.Router();
router.use(authMiddleware);

const MAX_SIZE = 1 * 1024 * 1024; // 1MB

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_SIZE },
});

const s3 = new S3Client({
  region: 'auto',
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

// Upload file
router.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return sendError(res, req, 400, 'No file provided', null, 'FILE_REQUIRED');
  }

  const ext = req.file.originalname.split('.').pop();
  const key = `uploads/${req.userId}/${uuidv4()}.${ext}`;

  try {
    await assertQuota(req.userId, 'upload_count', 1);
    await assertQuota(req.userId, 'upload_bytes', req.file.size);

    await s3.send(
      new PutObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME,
        Key: key,
        Body: req.file.buffer,
        ContentType: req.file.mimetype,
      })
    );

    const file = await recordFile({
      ownerId: req.userId,
      key,
      fileName: req.file.originalname,
      contentType: req.file.mimetype,
      size: req.file.size,
      visibility: 'private',
    });

    await recordUsage(req.userId, 'upload_count', 1, { file_id: file.id });
    await recordUsage(req.userId, 'upload_bytes', req.file.size, { file_id: file.id });

    res.json({
      id: file.id,
      key,
      file_name: req.file.originalname,
      size: req.file.size,
      content_type: req.file.mimetype,
    });
  } catch (err) {
    metrics.inc('upload_failures_total', { code: err.code || 'UPLOAD_FAILED' });
    return sendError(res, req, err.statusCode || 500, 'Upload failed', err);
  }
});

// Download private file (proxy from R2)
router.get('/:key(*)', async (req, res) => {
  try {
    const key = await assertCanReadR2Key(req.userId, req.params.key);
    const result = await s3.send(
      new GetObjectCommand({
        Bucket: process.env.R2_BUCKET_NAME,
        Key: key,
      })
    );

    res.set('Content-Type', result.ContentType || 'application/octet-stream');
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Content-Disposition', `attachment; filename="${key.split('/').pop()}"`);
    result.Body.pipe(res);
  } catch (err) {
    return sendError(res, req, err.statusCode || 404, 'File not found', err);
  }
});

module.exports = router;
