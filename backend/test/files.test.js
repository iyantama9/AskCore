jest.mock('../src/db', () => ({
  pool: {
    query: jest.fn(),
  },
}));

const { pool } = require('../src/db');
const {
  canReadR2Key,
  assertCanReadR2Key,
  isPublicKey,
  normalizeR2Key,
} = require('../src/utils/files');

describe('files utility authorization', () => {
  beforeEach(() => {
    pool.query.mockReset();
  });

  test.each([
    ['generated/1/image.png', true],
    ['browse/1/page.jpg', true],
    ['uploads/1/private.txt', false],
  ])('public key policy for %s', (key, expected) => {
    expect(isPublicKey(key)).toBe(expected);
  });

  test('normalizes app file URLs into R2 keys', () => {
    expect(normalizeR2Key('https://askcore.dev/api/files/uploads/7/a.txt')).toBe('uploads/7/a.txt');
    expect(normalizeR2Key('/uploads/7/a.txt')).toBe('uploads/7/a.txt');
  });

  test('allows public generated keys without DB lookup', async () => {
    await expect(canReadR2Key(10, 'generated/10/a.png')).resolves.toMatchObject({
      allowed: true,
      key: 'generated/10/a.png',
      visibility: 'public',
    });
    expect(pool.query).not.toHaveBeenCalled();
  });

  test('allows owner to read private file metadata', async () => {
    pool.query.mockResolvedValue({ rows: [{ owner_id: 10, visibility: 'private' }] });

    await expect(canReadR2Key(10, 'uploads/10/a.txt')).resolves.toMatchObject({
      allowed: true,
      key: 'uploads/10/a.txt',
      visibility: 'private',
    });
  });

  test('blocks non-owner private file metadata', async () => {
    pool.query.mockResolvedValue({ rows: [{ owner_id: 10, visibility: 'private' }] });

    await expect(canReadR2Key(11, 'uploads/10/a.txt')).resolves.toMatchObject({
      allowed: false,
      key: 'uploads/10/a.txt',
    });
  });

  test('allows legacy upload prefix for same user only', async () => {
    pool.query.mockResolvedValue({ rows: [] });

    await expect(canReadR2Key(10, 'uploads/10/legacy.txt')).resolves.toMatchObject({
      allowed: true,
      key: 'uploads/10/legacy.txt',
    });
    await expect(canReadR2Key(11, 'uploads/10/legacy.txt')).resolves.toMatchObject({
      allowed: false,
      key: 'uploads/10/legacy.txt',
    });
  });

  test('assertCanReadR2Key throws 404 style error when denied', async () => {
    pool.query.mockResolvedValue({ rows: [{ owner_id: 10, visibility: 'private' }] });

    await expect(assertCanReadR2Key(11, 'uploads/10/a.txt')).rejects.toMatchObject({
      statusCode: 404,
      message: 'File not found',
    });
  });
});
