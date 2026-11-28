import test from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = new URL('../native/ios-app/', import.meta.url)

// Keys of the top-level `strings` object, in file order, including a key that is written twice.
// JSON.parse keeps only one of a repeated key, which is how a second Outfits entry can hide the
// translations Xcode already ships.
function stringCatalogKeys(text) {
  const keys = []
  let i = 0
  let depth = 0
  let stringsDepth = null
  while (i < text.length) {
    const c = text[i]
    if (c === '"') {
      const end = endOfString(text, i)
      const value = JSON.parse(text.slice(i, end))
      let k = end
      while (k < text.length && /\s/.test(text[k])) k++
      if (text[k] === ':') {
        if (stringsDepth === null && depth === 1 && value === 'strings') stringsDepth = depth + 1
        else if (stringsDepth !== null && depth === stringsDepth) keys.push(value)
      }
      i = end
      continue
    }
    if (c === '{') depth++
    else if (c === '}') {
      if (stringsDepth !== null && depth === stringsDepth) stringsDepth = null
      depth--
    }
    i++
  }
  return keys
}

function endOfString(text, open) {
  let i = open + 1
  while (i < text.length) {
    if (text[i] === '\\') { i += 2; continue }
    if (text[i] === '"') return i + 1
    i++
  }
  return text.length
}

function duplicates(keys) {
  const seen = new Map()
  const repeated = []
  for (const key of keys) {
    seen.set(key, (seen.get(key) ?? 0) + 1)
    if (seen.get(key) === 2) repeated.push(key)
  }
  return repeated
}

function catalogs() {
  const found = []
  const walk = (dir) => {
    for (const name of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, name.name)
      if (name.isDirectory()) walk(path)
      else if (name.name.endsWith('.xcstrings')) found.push(path)
    }
  }
  walk(fileURLToPath(root))
  return found
}

test('a repeated catalog key is reported in file order', () => {
  const keys = stringCatalogKeys(`{
    "sourceLanguage": "en",
    "strings": {
      "Outfits": { "localizations": { "zh-Hans": { "stringUnit": { "value": "套装" } } } },
      "About": { "localizations": {} },
      "Outfits": { "localizations": { "zh-Hans": { "stringUnit": { "value": "装扮" } } } }
    },
    "version": "1.0"
  }`)
  assert.deepEqual(duplicates(keys), ['Outfits'])
  assert.equal(JSON.parse(`{ "Outfits": "套装", "Outfits": "装扮" }`).Outfits, '装扮')
})

test('string catalogs have one entry per key', () => {
  const problems = []
  for (const path of catalogs()) {
    const text = readFileSync(path, 'utf8')
    const repeated = duplicates(stringCatalogKeys(text))
    if (repeated.length) problems.push(`${path}: ${repeated.join(', ')}`)
  }
  assert.deepEqual(problems, [], problems.join('\n'))
})

test('Outfits keeps the wardrobe wording the catalog compiler already ships', () => {
  const text = readFileSync(new URL('../native/ios-app/Shared/Localizable.xcstrings', import.meta.url), 'utf8')
  assert.deepEqual(duplicates(stringCatalogKeys(text)).filter((key) => key === 'Outfits'), [])
  const outfits = JSON.parse(text).strings.Outfits
  assert.equal(outfits.localizations['zh-Hans'].stringUnit.value, '套装')
  assert.equal(outfits.localizations['zh-Hant'].stringUnit.value, '套裝')
  assert.equal(outfits.extractionState, 'manual')
})
