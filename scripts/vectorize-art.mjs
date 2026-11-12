import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

// Trace the downloaded Freepik artwork into color-separated editable paths.
const [source, target, count = '6', omitBackground] = process.argv.slice(2);
const [width, height] = execFileSync('magick', ['identify', '-format', '%w %h', source], {encoding:'utf8'}).split(' ').map(Number);
const pixels = execFileSync('magick', [source, '-alpha', 'off', '+dither', '-colors', count, '-depth', '8', 'rgb:-'], {maxBuffer: 32 * 1024 * 1024});
const colors = new Map();
for (let i = 0; i < pixels.length; i += 3) {
  const key = pixels.subarray(i, i + 3).toString('hex');
  colors.set(key, (colors.get(key) || 0) + 1);
}
const background = pixels.subarray(0, 3).toString('hex');
const layers = [];
for (const [color] of [...colors].sort((a,b) => b[1]-a[1])) {
  if (omitBackground && color === background) continue;
  const bitmap = Buffer.alloc(Math.ceil(width / 8) * height);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const i = (y * width + x) * 3;
    if (pixels.subarray(i, i + 3).toString('hex') === color) bitmap[y * Math.ceil(width/8) + (x >> 3)] |= 128 >> (x % 8);
  }
  const mask = '.build/vectorize/mask.pbm';
  fs.writeFileSync(mask, Buffer.concat([Buffer.from(`P4\n${width} ${height}\n`), bitmap]));
  const svg = execFileSync('potrace', [mask, '-s', '-o', '-', '--turdsize', '14', '--opttolerance', '0.3'], {encoding:'utf8'});
  layers.push(svg.match(/<g[\s\S]*<\/g>/)[0].replace('fill="#000000"', `fill="#${color}"`));
}
fs.writeFileSync(target, `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${layers.join('\n')}</svg>`);
console.log(`Created ${target}: ${layers.length} editable color layers.`);
