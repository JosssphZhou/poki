import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import sharp from 'sharp';
import { stateDir } from './config.mjs';

export async function screenshotReply(frame, { full_resolution, max_width } = {}) {
  let data, width, height, mimeType;
  if (full_resolution) {
    data = frame.original;
    ({ width, height } = await sharp(data).metadata());
    mimeType = 'image/png';
  } else {
    const source = sharp(max_width === undefined ? frame.original : frame.data);
    let resized;
    if (max_width !== undefined) {
      resized = await source.resize({ width: Math.round(max_width) })
        .jpeg({ quality: 90 }).toBuffer({ resolveWithObject: true });
    } else {
      let edge = 800;
      do {
        resized = await source.clone().resize({ width: edge, height: edge, fit: 'inside', withoutEnlargement: true })
          .jpeg({ quality: 72, mozjpeg: true }).toBuffer({ resolveWithObject: true });
        edge = Math.floor(edge * 0.8);
      } while (resized.data.length > 225_000);
    }
    ({ data, info: { width, height } } = resized);
    mimeType = 'image/jpeg';
  }

  const directory = join(stateDir, 'evidence', 'screenshots');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const original_path = join(directory, `${frame.id}.png`);
  await writeFile(original_path, frame.original, { mode: 0o600 });
  return {
    screenshot: { width, height, original_path },
    image: { type: 'image', data: data.toString('base64'), mimeType },
  };
}
