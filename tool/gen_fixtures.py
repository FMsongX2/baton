#!/usr/bin/env python3
# 테스트용 최소 PNG 생성. 이미지→PDF의 페이지 비율 계산을 검증하려면 가로·세로 두 종류가 필요함.

import struct
import sys
import zlib
from pathlib import Path


def png(w: int, h: int, rgb: tuple) -> bytes:
    """단색 RGB PNG 바이트를 만듦. 필터 타입 0 스캔라인만 씀."""
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw))
            + chunk(b'IEND', b''))


def main() -> None:
    """가로형·세로형 PNG를 test/fixtures 아래에 씀."""
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'test/fixtures')
    out.mkdir(parents=True, exist_ok=True)
    (out / 'landscape_200x100.png').write_bytes(png(200, 100, (220, 220, 220)))
    (out / 'portrait_100x200.png').write_bytes(png(100, 200, (180, 180, 180)))
    print(f'wrote fixtures to {out}')


if __name__ == '__main__':
    main()
