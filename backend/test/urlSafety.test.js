const dns = require('dns').promises;
const { validatePublicHttpUrl, isPrivateAddress } = require('../src/utils/urlSafety');

jest.mock('dns', () => ({
  promises: {
    lookup: jest.fn(),
  },
}));

describe('urlSafety', () => {
  beforeEach(() => {
    dns.lookup.mockReset();
  });

  test.each([
    '127.0.0.1',
    '10.0.0.1',
    '172.16.0.1',
    '192.168.1.1',
    '169.254.169.254',
    '::1',
    'fc00::1',
    'fe80::1',
  ])('detects private address %s', (address) => {
    expect(isPrivateAddress(address)).toBe(true);
  });

  test('allows public HTTPS URLs', async () => {
    dns.lookup.mockResolvedValue([{ address: '93.184.216.34', family: 4 }]);

    await expect(validatePublicHttpUrl('https://example.com/path')).resolves.toBe(
      'https://example.com/path'
    );
  });

  test('defaults bare domains to HTTPS', async () => {
    dns.lookup.mockResolvedValue([{ address: '93.184.216.34', family: 4 }]);

    await expect(validatePublicHttpUrl('example.com')).resolves.toBe('https://example.com/');
  });

  test.each(['file:///etc/passwd', 'ftp://example.com/file'])('blocks non HTTP URL %s', async (url) => {
    await expect(validatePublicHttpUrl(url)).rejects.toThrow('Only HTTP/HTTPS URLs are allowed');
  });

  test.each(['http://localhost', 'http://app.localhost'])('blocks localhost URL %s', async (url) => {
    await expect(validatePublicHttpUrl(url)).rejects.toThrow('Localhost URLs are not allowed');
  });

  test('blocks private IP host directly', async () => {
    await expect(validatePublicHttpUrl('http://192.168.1.20')).rejects.toThrow(
      'Private network URLs are not allowed'
    );
  });

  test('blocks host resolving to private IP', async () => {
    dns.lookup.mockResolvedValue([{ address: '10.0.0.5', family: 4 }]);

    await expect(validatePublicHttpUrl('https://example.com')).rejects.toThrow(
      'Private network URLs are not allowed'
    );
  });
});
