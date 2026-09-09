#!/usr/bin/env python3
# 클럭 드리프트 로그 분석. 오디오 엔진 시각과 시스템 시계의 차이가 진동인지 누적인지 가름.
# 진동은 오디오 버퍼 경계 때문이라 무해하고, 누적은 템포 자체가 틀어진다는 뜻.

import re
import sys
from pathlib import Path

PAT = re.compile(r'SPIKE t=(\d+)s diff=(-?[\d.]+)ms drift=(-?[\d.]+)ppm scheduled=(\d+)')


def main() -> None:
    """로그에서 (t, diff) 쌍을 뽑아 추세와 진폭을 보고함."""
    path = Path(sys.argv[1] if len(sys.argv) > 1 else 'clock_drift.log')
    rows = []
    for line in path.read_text(errors='ignore').splitlines():
        m = PAT.search(line)
        if m:
            rows.append((int(m.group(1)), float(m.group(2)), int(m.group(4))))
    if len(rows) < 10:
        print(f'샘플 부족: {len(rows)}개')
        return

    rows.sort()
    ts = [r[0] for r in rows]
    ds = [r[1] for r in rows]
    n = len(rows)

    # 최소제곱 기울기. ms/s 를 ppm으로 바꾸면 곧 누적 드리프트율
    mt = sum(ts) / n
    md = sum(ds) / n
    num = sum((t - mt) * (d - md) for t, d in zip(ts, ds))
    den = sum((t - mt) ** 2 for t in ts)
    slope = num / den if den else 0.0

    print(f'샘플 {n}개, 구간 {ts[0]}s ~ {ts[-1]}s ({(ts[-1] - ts[0]) / 60:.1f}분)')
    print(f'차이 범위 {min(ds):.2f} ~ {max(ds):.2f} ms (진폭 {max(ds) - min(ds):.2f} ms)')
    print(f'차이 평균 {md:.2f} ms')
    print(f'추세 {slope * 1000:.2f} us/s = {slope * 1000:.1f} ppm')
    print(f'1시간 환산 누적 {slope * 3600:.1f} ms')

    # 예약 클릭 수가 120bpm(초당 2개)과 맞는지. 빠지면 소리가 새는 것
    span = ts[-1] - ts[0]
    got = rows[-1][2] - rows[0][2]
    print(f'클릭 예약 {got}개 / 기대 {span * 2}개 (차이 {got - span * 2})')


if __name__ == '__main__':
    main()
