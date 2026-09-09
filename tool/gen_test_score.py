#!/usr/bin/env python3
# 실기기 확인용 가짜 악보 이미지 생성. 오선과 마디선을 그려 페이지 넘김이 눈에 보이게 함.
# 페이지 번호는 좌상단 사각형 개수로 표시함. 폰트 없이 구분하려는 것.

import struct
import sys
import zlib
from pathlib import Path

W, H = 900, 1250
STAFF_TOP = 180
STAFF_GAP = 170       # 오선 묶음 사이 간격
LINE_GAP = 14         # 오선 한 줄 간격
STAVES = 6
BARS_PER_STAFF = 4


def blank() -> list:
    """흰 배경 픽셀 버퍼를 만듦."""
    return [bytearray(b'\xff' * (W * 3)) for _ in range(H)]


def hline(buf, y: int, x0: int, x1: int) -> None:
    """가로 검은 선을 그림."""
    if not (0 <= y < H):
        return
    for x in range(max(0, x0), min(W, x1)):
        buf[y][x * 3:x * 3 + 3] = b'\x00\x00\x00'


def vline(buf, x: int, y0: int, y1: int) -> None:
    """세로 검은 선을 그림. 마디선용."""
    if not (0 <= x < W):
        return
    for y in range(max(0, y0), min(H, y1)):
        buf[y][x * 3:x * 3 + 3] = b'\x00\x00\x00'


def rect(buf, x0: int, y0: int, w: int, h: int) -> None:
    """채운 검은 사각형. 페이지 번호 표시용."""
    for y in range(y0, min(H, y0 + h)):
        for x in range(x0, min(W, x0 + w)):
            buf[y][x * 3:x * 3 + 3] = b'\x00\x00\x00'


def page(n: int) -> bytes:
    """오선 6묶음과 마디선을 그린 한 페이지를 PNG로 만듦."""
    buf = blank()
    for i in range(n):
        rect(buf, 60 + i * 46, 70, 34, 34)
    for s in range(STAVES):
        top = STAFF_TOP + s * STAFF_GAP
        for line in range(5):
            hline(buf, top + line * LINE_GAP, 60, W - 60)
        bottom = top + 4 * LINE_GAP
        for b in range(BARS_PER_STAFF + 1):
            vline(buf, 60 + b * ((W - 120) // BARS_PER_STAFF), top, bottom)

    raw = b''.join(b'\x00' + bytes(row) for row in buf)

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 6))
            + chunk(b'IEND', b''))


def main() -> None:
    """페이지 여러 장을 out 디렉토리에 씀. 각 페이지는 오선 6묶음 × 4마디 = 24마디."""
    out = Path(sys.argv[1] if len(sys.argv) > 1 else 'test_score')
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    out.mkdir(parents=True, exist_ok=True)
    for i in range(1, count + 1):
        (out / f'page{i}.png').write_bytes(page(i))
    print(f'{count} pages -> {out} (페이지당 {STAVES * BARS_PER_STAFF}마디)')


if __name__ == '__main__':
    main()
