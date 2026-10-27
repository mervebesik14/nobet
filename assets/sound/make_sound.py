"""Nöbetçi bildirim sesini üretir: defibrilatör (elektroşok cihazı) sesi.

Sentezle üretilir (kayıt değildir), lisans gerektirmez. Üç bölüm:
1. Şarj: ~2 sn yükselen vınlama (600 → 3200 Hz).
2. Hazır: üç kısa bip (1 kHz).
3. Şok: kısa elektrik çıtırtısı ve alçak "güm".

Kullanım: python3 assets/sound/make_sound.py
Çıktı: android/app/src/main/res/raw/defibrilator.wav ve
ios/Runner/defibrilator.wav (16 bit, 44,1 kHz, mono; iOS bildirim sesi
sınırı 30 sn, bu ses ~3,8 sn).
"""

import os
import wave

import numpy as np

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUTPUTS = [
    os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'raw',
                 'defibrilator.wav'),
    os.path.join(ROOT, 'ios', 'Runner', 'defibrilator.wav'),
]


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def fade(x, inn=0.01, out=0.02):
    n_in, n_out = int(RATE * inn), int(RATE * out)
    env = np.ones_like(x)
    env[:n_in] = np.linspace(0, 1, n_in)
    env[-n_out:] = np.linspace(1, 0, n_out)
    return x * env


def charge(seconds=2.0):
    # Üstel yükselen frekans; faz integrali ile kesintisiz.
    tt = t(seconds)
    f0, f1 = 600.0, 3200.0
    k = np.log(f1 / f0) / seconds
    phase = 2 * np.pi * f0 * (np.exp(k * tt) - 1) / k
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase)
    # Hafif titreme ve giderek artan ses.
    tremolo = 1 + 0.08 * np.sin(2 * np.pi * 28 * tt)
    env = np.linspace(0.25, 1.0, tt.size) ** 1.5
    return fade(tone * tremolo * env * 0.5, out=0.03)


def beep(seconds=0.14, freq=1000.0):
    tt = t(seconds)
    return fade(0.55 * np.sin(2 * np.pi * freq * tt), 0.005, 0.01)


def silence(seconds):
    return np.zeros(int(RATE * seconds))


def shock(seconds=0.6):
    rng = np.random.default_rng(16)
    tt = t(seconds)
    # Elektrik çıtırtısı: hızla sönen gürültü.
    crack = rng.normal(0, 1, tt.size) * np.exp(-tt * 28)
    # Alçak "güm": 70 → 40 Hz inen, sönen sinüs.
    freq = 70 - 30 * tt / seconds
    thump = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-tt * 7)
    return fade(0.6 * crack + 0.9 * thump, 0.001, 0.05)


def main():
    parts = [
        charge(),
        silence(0.12),
        beep(), silence(0.08), beep(), silence(0.08), beep(),
        silence(0.25),
        shock(),
        silence(0.2),
    ]
    audio = np.concatenate(parts)
    audio = audio / np.max(np.abs(audio)) * 0.89  # ≈ -1 dBFS
    pcm = (audio * 32767).astype('<i2').tobytes()
    for path in OUTPUTS:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm)
        print(path, f'{len(audio) / RATE:.2f} sn')


if __name__ == '__main__':
    main()
