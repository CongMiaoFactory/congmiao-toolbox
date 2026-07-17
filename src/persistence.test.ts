import { describe, expect, it } from 'vitest';
import { encodeWallpaper } from './persistence';

describe('wallpaper validation', () => {
  it('rejects non-image files without replacing the current wallpaper', async () => {
    const file = new File(['plain text'], 'notes.txt', { type: 'text/plain' });
    await expect(encodeWallpaper(file)).rejects.toThrow('请选择图片文件');
  });

  it('rejects images larger than the configured limit', async () => {
    const file = new File([new Uint8Array(15 * 1024 * 1024 + 1)], 'large.png', { type: 'image/png' });
    await expect(encodeWallpaper(file)).rejects.toThrow('图片不能超过 15 MB');
  });
});
