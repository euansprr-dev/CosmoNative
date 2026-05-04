import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outputPath = join(root, "public", "audio", "cosmo-pulse.wav");

const sampleRate = 44100;
const durationSeconds = 75;
const samples = sampleRate * durationSeconds;
const channels = 1;
const bytesPerSample = 2;
const dataSize = samples * channels * bytesPerSample;
const buffer = Buffer.alloc(44 + dataSize);

const writeString = (offset, value) => buffer.write(value, offset, "ascii");

writeString(0, "RIFF");
buffer.writeUInt32LE(36 + dataSize, 4);
writeString(8, "WAVE");
writeString(12, "fmt ");
buffer.writeUInt32LE(16, 16);
buffer.writeUInt16LE(1, 20);
buffer.writeUInt16LE(channels, 22);
buffer.writeUInt32LE(sampleRate, 24);
buffer.writeUInt32LE(sampleRate * channels * bytesPerSample, 28);
buffer.writeUInt16LE(channels * bytesPerSample, 32);
buffer.writeUInt16LE(16, 34);
writeString(36, "data");
buffer.writeUInt32LE(dataSize, 40);

const notes = [110, 146.83, 174.61, 220, 261.63, 329.63, 392, 440];

for (let i = 0; i < samples; i += 1) {
  const t = i / sampleRate;
  const beat = (t * 118) / 60;
  const beatPhase = beat % 1;
  const bar = Math.floor(beat / 4);
  const note = notes[(bar + Math.floor(beat / 2)) % notes.length];
  const kick = Math.exp(-beatPhase * 20) * Math.sin(2 * Math.PI * (48 + beatPhase * 36) * t);
  const hatPhase = (beat * 2) % 1;
  const hat = Math.exp(-hatPhase * 34) * (Math.sin(2 * Math.PI * 6500 * t) > 0 ? 1 : -1);
  const bass = Math.sin(2 * Math.PI * note * t) * (0.34 + 0.1 * Math.sin(2 * Math.PI * 0.08 * t));
  const pad =
    Math.sin(2 * Math.PI * note * 2 * t) * 0.11 +
    Math.sin(2 * Math.PI * note * 3 * t) * 0.055;
  const rise = Math.min(1, t / 5) * Math.min(1, (durationSeconds - t) / 5);
  const sidechain = 0.66 + 0.34 * Math.min(1, beatPhase * 2.4);
  const sample = (kick * 0.32 + hat * 0.045 + (bass * 0.26 + pad) * sidechain) * rise;
  const limited = Math.max(-0.92, Math.min(0.92, sample));

  buffer.writeInt16LE(Math.round(limited * 32767), 44 + i * bytesPerSample);
}

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, buffer);
console.log(outputPath);
