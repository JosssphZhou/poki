// Reading Info.plist without plutil. Xcode's plutil only exists on macOS, and an
// .ipa that came from a build carries the binary form, so both forms are read here.
import { readFile } from 'node:fs/promises';

const TRAILER = 32;
const utf8 = new TextDecoder('utf-8', { fatal: false });

function parseBinary(buffer) {
  if (buffer.toString('latin1', 0, 8) !== 'bplist00') throw new Error('Not a binary property list.');
  const trailer = buffer.subarray(buffer.length - TRAILER);
  const offsetSize = trailer[6], referenceSize = trailer[7];
  const number = (start, size) => {
    let value = 0;
    for (let index = 0; index < size; index++) value = value * 256 + trailer[start + index];
    return value;
  };
  const objectCount = number(8, 8), topObject = number(16, 8), tableOffset = number(24, 8);
  if (!objectCount || tableOffset + objectCount * offsetSize > buffer.length) throw new Error('Truncated binary property list.');

  const offsetAt = index => {
    let value = 0;
    for (let byte = 0; byte < offsetSize; byte++) value = value * 256 + buffer[tableOffset + index * offsetSize + byte];
    return value;
  };
  const seen = new Map();
  const readObject = index => {
    if (seen.has(index)) return seen.get(index);
    const start = offsetAt(index);
    const marker = buffer[start];
    const kind = marker >> 4, info = marker & 0x0f;
    let cursor = start + 1;
    const length = () => {
      if (info !== 0x0f) return info;
      const extended = buffer[cursor]; cursor += 1;
      const size = 1 << (extended & 0x0f);
      let value = 0;
      for (let byte = 0; byte < size; byte++) value = value * 256 + buffer[cursor + byte];
      cursor += size;
      return value;
    };
    const reference = () => {
      let value = 0;
      for (let byte = 0; byte < referenceSize; byte++) value = value * 256 + buffer[cursor + byte];
      cursor += referenceSize;
      return value;
    };
    let value;
    switch (kind) {
      case 0x0:
        value = info === 0x08 ? false : info === 0x09 ? true : null;
        break;
      case 0x1: {
        const size = 1 << info;
        value = 0;
        for (let byte = 0; byte < size; byte++) value = value * 256 + buffer[start + 1 + byte];
        break;
      }
      case 0x2: {
        const size = 1 << info;
        value = size === 4 ? buffer.readFloatBE(start + 1) : buffer.readDoubleBE(start + 1);
        break;
      }
      case 0x3: {
        const seconds = buffer.readDoubleBE(start + 1);
        value = new Date(Date.UTC(2001, 0, 1) + seconds * 1000).toISOString();
        break;
      }
      case 0x4: {
        const count = length();
        value = buffer.subarray(cursor, cursor + count);
        break;
      }
      case 0x5: {
        const count = length();
        value = buffer.toString('latin1', cursor, cursor + count);
        break;
      }
      case 0x6: {
        const count = length();
        const bytes = buffer.subarray(cursor, cursor + count * 2);
        value = bytes.swap16().toString('utf16le');
        break;
      }
      case 0x8: {
        const count = (info + 1) * 2;
        value = 0;
        for (let byte = 0; byte < count; byte++) value = value * 256 + buffer[start + 1 + byte];
        break;
      }
      case 0xa:
      case 0xc: {
        const count = length();
        value = [];
        seen.set(index, value);
        for (let item = 0; item < count; item++) value.push(readObject(reference()));
        return value;
      }
      case 0xd: {
        const count = length();
        value = {};
        seen.set(index, value);
        for (let item = 0; item < count; item++) {
          const key = readObject(reference());
          value[String(key)] = readObject(reference());
        }
        return value;
      }
      default:
        throw new Error(`Unsupported binary property list object kind 0x${kind.toString(16)}.`);
    }
    seen.set(index, value);
    return value;
  };
  return readObject(topObject);
}

function parseXml(text) {
  const value = name => [...text.matchAll(new RegExp(`<key>\\s*${name}\\s*</key>\\s*<string>([\\s\\S]*?)</string>`, 'g'))][0]?.[1];
  return { CFBundleIdentifier: value('CFBundleIdentifier'), CFBundleExecutable: value('CFBundleExecutable'), CFBundleDisplayName: value('CFBundleDisplayName'), CFBundleName: value('CFBundleName'), CFBundleShortVersionString: value('CFBundleShortVersionString') };
}

export async function parsePlistFile(path) {
  const buffer = await readFile(path);
  if (buffer.length > 8 && buffer.toString('latin1', 0, 8) === 'bplist00') return parseBinary(buffer);
  return parseXml(buffer.toString('utf8'));
}

export async function readPlistValue(path, key) {
  const parsed = await parsePlistFile(path);
  const value = parsed?.[key];
  if (typeof value !== 'string' || !value) throw new Error(`Info.plist has no ${key}.`);
  return value;
}
