// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  final outDir = Directory('assets/audio');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // 1. tap.wav (40ms soft mechanical click)
  generateWav(
    File('assets/audio/tap.wav'),
    durationSeconds: 0.05,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 90);
      return math.sin(2 * math.pi * 850 * t) * decay * 0.7;
    },
  );

  // 2. word_success.wav (350ms ascending harmonic chime)
  generateWav(
    File('assets/audio/word_success.wav'),
    durationSeconds: 0.35,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 8);
      double freq = 523.25; // C5
      if (t > 0.20) {
        freq = 783.99; // G5
      } else if (t > 0.10) {
        freq = 659.25; // E5
      }
      final bell = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * freq * 2 * t);
      return bell * decay * 0.6;
    },
  );

  // 3. word_error.wav (250ms soft low buzzer)
  generateWav(
    File('assets/audio/word_error.wav'),
    durationSeconds: 0.25,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 12);
      final s = math.sin(2 * math.pi * 160 * t) * 0.5 + math.sin(2 * math.pi * 165 * t) * 0.5;
      return s * decay * 0.7;
    },
  );

  // 4. countdown.wav (80ms crisp woodblock / timer tick)
  generateWav(
    File('assets/audio/countdown.wav'),
    durationSeconds: 0.08,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 70);
      return math.sin(2 * math.pi * 1200 * t) * decay * 0.65;
    },
  );

  // 5. victory.wav (650ms celebratory chords)
  generateWav(
    File('assets/audio/victory.wav'),
    durationSeconds: 0.65,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 4);
      double f1 = 523.25;
      double f2 = 659.25;
      if (t > 0.28) {
        f1 = 783.99;
        f2 = 1046.50;
      } else if (t > 0.14) {
        f1 = 659.25;
        f2 = 783.99;
      }
      final s = 0.5 * math.sin(2 * math.pi * f1 * t) + 0.5 * math.sin(2 * math.pi * f2 * t);
      return s * decay * 0.75;
    },
  );

  // 6. defeat.wav (500ms soft descending tone)
  generateWav(
    File('assets/audio/defeat.wav'),
    durationSeconds: 0.50,
    sampleRate: 44100,
    generator: (t) {
      final decay = math.exp(-t * 5);
      double freq = 392.00; // G4
      if (t > 0.25) {
        freq = 311.13; // Eb4
      }
      final s = math.sin(2 * math.pi * freq * t);
      return s * decay * 0.65;
    },
  );

  print('Audio assets generated successfully.');
}

void generateWav(
  File file, {
  required double durationSeconds,
  required int sampleRate,
  required double Function(double t) generator,
}) {
  final numSamples = (durationSeconds * sampleRate).toInt();
  final byteRate = sampleRate * 2;
  final dataSize = numSamples * 2;
  final fileSize = 36 + dataSize;

  final buffer = BytesBuilder();

  // RIFF header
  buffer.add('RIFF'.codeUnits);
  buffer.add(_int32(fileSize));
  buffer.add('WAVE'.codeUnits);

  // fmt chunk
  buffer.add('fmt '.codeUnits);
  buffer.add(_int32(16));
  buffer.add(_int16(1));
  buffer.add(_int16(1));
  buffer.add(_int32(sampleRate));
  buffer.add(_int32(byteRate));
  buffer.add(_int16(2));
  buffer.add(_int16(16));

  // data chunk
  buffer.add('data'.codeUnits);
  buffer.add(_int32(dataSize));

  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sample = generator(t).clamp(-1.0, 1.0);
    final intSample = (sample * 32767).toInt().clamp(-32768, 32767);
    buffer.add(_int16(intSample));
  }

  file.writeAsBytesSync(buffer.toBytes());
}

List<int> _int16(int val) {
  final bd = ByteData(2)..setInt16(0, val, Endian.little);
  return bd.buffer.asUint8List();
}

List<int> _int32(int val) {
  final bd = ByteData(4)..setInt32(0, val, Endian.little);
  return bd.buffer.asUint8List();
}
