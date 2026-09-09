#!/usr/bin/env python3
# 메트로놈 클릭 WAV 생성. 에셋을 바이너리로 커밋하지 않고 이 스크립트로 재생성함.
# 출력: assets/sounds/click_hi.wav (강박), click_lo.wav (약박)

import math
import struct
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 44100
DURATION = 0.030      # 30ms. 룩어헤드 스케줄 간격보다 훨씬 짧아야 함
ATTACK = 0.0006       # 0.6ms 어택 램프. 없으면 시작 지점에서 딱 소리가 남
DECAY_TAU = 0.007     # 지수 감쇠 시상수


def render(freq: float, peak: float) -> bytes:
    """사인 기본파 + 2배음을 지수 감쇠시켜 16bit mono PCM 프레임을 만듦."""
    n = int(SAMPLE_RATE * DURATION)
    attack_n = max(1, int(SAMPLE_RATE * ATTACK))
    frames = bytearray()
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t / DECAY_TAU)
        if i < attack_n:
            env *= i / attack_n
        # 끝에서 정확히 0으로 수렴시켜 꼬리 클릭을 없앰
        env *= 1.0 - (i / (n - 1)) ** 4
        s = math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(4 * math.pi * freq * t)
        frames += struct.pack('<h', int(max(-1.0, min(1.0, s / 1.35 * env * peak)) * 32767))
    return bytes(frames)


def write(path: Path, data: bytes) -> None:
    """16bit mono 44.1kHz WAV로 저장함. 상위 디렉토리는 미리 만듦."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(data)


def main() -> None:
    """강박/약박 두 클릭을 assets/sounds 아래에 생성함."""
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'assets/sounds')
    write(out / 'click_hi.wav', render(2000.0, 0.95))
    write(out / 'click_lo.wav', render(1300.0, 0.72))
    print(f'wrote {out}/click_hi.wav, {out}/click_lo.wav')


if __name__ == '__main__':
    main()
