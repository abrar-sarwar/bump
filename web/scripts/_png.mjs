import { readFileSync, writeFileSync } from 'node:fs'
import { inflateSync, deflateSync } from 'node:zlib'

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

export function decode(path) {
  const buf = readFileSync(path)
  if (!buf.subarray(0, 8).equals(PNG_SIG)) throw new Error('not a PNG')
  let off = 8, ihdr = null, idat = [], plte = null, trns = null
  while (off < buf.length) {
    const len = buf.readUInt32BE(off)
    const type = buf.toString('ascii', off + 4, off + 8)
    const data = buf.subarray(off + 8, off + 8 + len)
    if (type === 'IHDR') ihdr = {
      width: data.readUInt32BE(0), height: data.readUInt32BE(4),
      depth: data[8], colorType: data[9], interlace: data[12],
    }
    else if (type === 'IDAT') idat.push(data)
    else if (type === 'PLTE') plte = Buffer.from(data)
    else if (type === 'tRNS') trns = Buffer.from(data)
    else if (type === 'IEND') break
    off += 12 + len
  }
  if (ihdr.interlace) throw new Error('interlaced PNG unsupported')
  if (ihdr.depth !== 8) throw new Error(`bit depth ${ihdr.depth} unsupported`)

  const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }
  const ch = CHANNELS[ihdr.colorType]
  const { width: W, height: H } = ihdr
  const raw = inflateSync(Buffer.concat(idat))
  const bpp = ch
  const stride = W * bpp
  const out = Buffer.alloc(H * stride)

  // Undo per-scanline filtering (PNG spec 9.2)
  for (let y = 0; y < H; y++) {
    const filter = raw[y * (stride + 1)]
    const src = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride)
    const cur = out.subarray(y * stride, (y + 1) * stride)
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride)
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp] : 0
      const b = prev[i]
      const c = i >= bpp ? prev[i - bpp] : 0
      let v = src[i]
      if (filter === 1) v += a
      else if (filter === 2) v += b
      else if (filter === 3) v += (a + b) >> 1
      else if (filter === 4) {
        const p = a + b - c
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
      }
      cur[i] = v & 0xff
    }
  }

  // Normalise everything to RGBA
  const rgba = Buffer.alloc(W * H * 4)
  for (let i = 0; i < W * H; i++) {
    let r, g, bl, al = 255
    if (ihdr.colorType === 0) { r = g = bl = out[i] }
    else if (ihdr.colorType === 4) { r = g = bl = out[i * 2]; al = out[i * 2 + 1] }
    else if (ihdr.colorType === 2) { r = out[i * 3]; g = out[i * 3 + 1]; bl = out[i * 3 + 2] }
    else if (ihdr.colorType === 6) { r = out[i * 4]; g = out[i * 4 + 1]; bl = out[i * 4 + 2]; al = out[i * 4 + 3] }
    else if (ihdr.colorType === 3) {
      const idx = out[i]; r = plte[idx * 3]; g = plte[idx * 3 + 1]; bl = plte[idx * 3 + 2]
      if (trns && idx < trns.length) al = trns[idx]
    }
    rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = bl; rgba[i * 4 + 3] = al
  }
  return { width: W, height: H, data: rgba }
}

function crc32(buf) {
  let c, crc = 0xffffffff
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    crc = c ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td))
  return Buffer.concat([len, td, crc])
}

export function encode({ width, height, data }, path) {
  const stride = width * 4
  const raw = Buffer.alloc(height * (stride + 1))
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0 // filter: none, keeps it simple and lossless
    data.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0
  writeFileSync(path, Buffer.concat([
    PNG_SIG, chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]))
}
