# Baton

악보를 템포에 맞춰 자동으로 넘겨 주는 앱. 정확한 메트로놈이 같은 시계를 공유함.
Flutter, iOS·Android.

## 동작 원리

오디오 엔진 시각(`SoLoud.getEngineTime()`)이 앱의 유일한 시계.
메트로놈 클릭과 페이지 넘김이 이 시계 하나를 읽어 긴 곡에서도 어긋나지 않음.
갤럭시 S24 실측 드리프트 0.0 ppm(17분, 클릭 누락 0/2082).

악보마다 bpm·박자표·페이지별 마디수를 두고, 시작하면 카운트인 뒤
페이지 체류 시간을 계산해 자동으로 넘김.

## 구조

| 경로 | 역할 |
|---|---|
| `lib/score/timeline.dart` | 타임라인 계산. 타이밍의 유일한 진실 |
| `lib/score/playback_engine.dart` | 클럭·클릭 예약·페이지 전환 결합 |
| `lib/metronome/clock.dart` | 재생 위치. 시간 제공자를 주입받음 |
| `lib/metronome/click_scheduler.dart` | 룩어헤드 클릭 예약, 지연 보정 |
| `lib/core/db/` | drift 스키마와 저장소 |
| `lib/library/` | 폴더 트리 |
| `lib/reader/` | 뷰어·필기·자동 넘김 |
| `lib/settings/pedal_keys.dart` | 페달 넘김 키 매핑. 기본값과 학습 결과 |
| `lib/billing/` | 메트로놈 언락(1회성)과 코인 묶음(소모성) 결제 |
| `lib/ads/ads.dart` | 광고 동의(UMP)·SDK 초기화와 앱 하단 배너 칸 |
| `lib/cloud/` | 서버 호출과 코인 지갑 |
| `lib/score/ai_analysis.dart` | AI가 읽은 마디수·템포를 반영하고 되돌림 |
| `server/` | Cloudflare Workers. OpenAI 키와 코인 원장을 여기에만 둠 |

임포트한 이미지·PDF는 입구에서 PDF 하나로 정규화함.
파일은 `<appDocuments>/scores/<nodeId>/source.pdf`에 두고 DB에는 상대경로만 저장함.
필기는 페이지 정규 좌표(0~1)로 저장해 원본 PDF를 건드리지 않음.

### 좌표계

pdfrx가 `pagePaintCallbacks`로 주는 `pageRect`는 확대·이동을 적용하기 전 **문서 좌표**임.
그리기 오버레이는 변환 밖에 있으므로 포인터 위치를 `PdfViewerController.globalToDocument`로
같은 계에 옮긴 뒤 정규화함. 화면 좌표를 그대로 쓰면 확대한 만큼 필기가 어긋난 자리에 저장됨.

### 일시정지와 재개

재개하면 멈춘 지점 앞의 마디선까지 되감고 그 구간을 카운트인으로 보여 줌.
되감은 구간의 클릭은 타임라인에 이미 있으므로 따로 만들지 않음.
카운트인 0마디로 두면 되감지 않고 멈춘 자리에서 이어감.

### 코인 소유권

서버가 발급한 토큰이 곧 코인 소유권임. 앱 DB(`baton.sqlite`)가 아니라 `device.json`에 따로 둠.
백업 zip은 `baton.sqlite`와 `scores/`만 담으므로, 백업을 남에게 넘겨도 코인은 넘어가지 않음.
기기를 바꿀 때는 복구 코드로 옮김.

복구 코드는 서버가 해시만 들고 있어 이미 발급한 것을 다시 보여 줄 수 없음.
설정에서 언제든 새로 받을 수 있고, 받으면 이전 코드는 무효가 됨(`POST /v1/device/recovery`).

### 백업

`baton.sqlite`와 `scores/`를 zip 하나로 묶음. 되살리기는 합치기가 아니라 교체이며,
기존 DB와 악보 디렉토리를 옆으로 밀어 두고 풀다가 실패하면 그대로 되돌림.
zip 안의 경로는 앱 디렉토리 밖을 가리키면 거부하고, DB에 담긴 `fileRel`도
`AppPaths.abs`가 같은 기준으로 검사함. 백업은 남이 만든 것일 수 있음.

### 삭제

삭제는 `deletedAt`만 찍고 파일은 두며, 휴지통에서 영구 삭제하거나 30일이 지나면
앱을 열 때 파일까지 함께 사라짐(`LibraryRepo.purge` / `purgeExpired`).
`deletedAt`은 drift 규칙대로 초 단위로 저장함.

## AI 마디수 읽기

코인을 써서 악보 전체를 GPT 비전에 넘기고 쪽별 마디수와 템포를 받아 설정에 반영함.
반영 직전 상태를 되돌리기 지점으로 남기므로 잘못 읽어도 한 번은 되돌릴 수 있음.

서버가 필요한 이유는 세 가지이며 각각 독립적으로 필수임.
API 키를 앱에 넣으면 추출되고, 코인 잔액을 앱에 두면 조작되며,
영수증을 앱에서만 확인하면 위조 구매를 막을 수 없음.

읽는 값의 한계를 알고 씀.
마디수는 페이지 안 도돌이표를 합산한 "그 페이지를 보는 동안 흐르는 마디 수"로 세게 함.
템포는 악보에 `♩=120` 같은 표기가 있을 때만 반영하고, 용어만 있거나 표기가 없으면 비워 둠.
확신이 낮다고 표시된 쪽은 결과 알림에 개수를 함께 보여 줌.
표지처럼 연주가 없는 쪽은 0마디로 들어와 바로 넘어감.
한 묶음이 실패해도 앞서 읽은 쪽은 반영하고, 못 읽은 부분을 알림에 함께 적음.

한 번에 보내는 쪽수는 서버의 `MAX_PAGES_PER_CALL`(8)이 정함.
1400px PNG 한 장이 base64로 1~3MB라 더 키우면 요청 본문과 메모리 한도를 먼저 넘김.
앱도 묶음 단위로 렌더하고 보낸 뒤 버려 쪽수와 무관하게 메모리가 일정함.

요청마다 `requestId`를 실어 보냄. 응답이 유실돼 다시 보내도 코인이 두 번 빠지지 않고,
이미 끝난 분석이면 서버가 저장해 둔 결과를 그대로 돌려줌.

### 서버 준비

```sh
cd server
npm install
npx wrangler d1 create baton          # 나온 database_id를 wrangler.toml에 채움
npm run db:init                       # 스키마 적용
npx wrangler secret put OPENAI_API_KEY
npm run deploy
```

영수증 검증을 붙이기 전에는 `BLOCK_UNVERIFIED_PURCHASES=1`이라 코인 적립이 막혀 있음.
`server/src/receipts.ts`의 verifyPurchase를 채우고 값을 `0`으로 바꿔야 실제 결제가 동작함.

스토어에는 비소모성 `baton_metronome`과 소모성 `baton_coins_10` / `_60` / `_150`을 등록함.
지급 코인 수는 `server/src/receipts.ts`의 COIN_PACKS가 정함.

### 앱에 서버 주소 넣기

```sh
flutter run --dart-define=BATON_API_BASE=https://baton-server.<계정>.workers.dev
```

주소가 비면 코인과 AI 기능이 화면에서 숨음. 나머지 기능은 그대로 동작함.

## 광고

앱 하단에 320×50 배너 하나를 둠. `MaterialApp.builder`에서 Navigator 밖에 붙이므로
화면을 오가도 다시 요청하지 않고, 폴더·설정처럼 전체 화면으로 여는 화면에도 남음.

악보 뷰어가 떠 있는 동안에는 배너 칸을 뺌. 넘김 탭 영역·재생줄과 맞닿아 오터치를 부르고
(AdMob 정책의 인터랙티브 요소 인접 금지), 어두운 무대용 반전 모드에서 밝은 광고가 번쩍임.

동의 확인(UMP) 전에는 광고 요청을 보내지 않음. 동의가 필요한 지역이면 설정에
'광고 개인정보 옵션'이 나타남. 동의 메시지는 AdMob 콘솔의 Privacy & messaging에서 만듦.

디버그·프로필은 구글 공식 테스트 ID를 씀. 개발 중 실제 광고를 누르면 무효 트래픽으로
계정이 막힐 수 있음. 실제 ID는 출시 빌드에서만 넣음.

| 값 | 넣는 곳 |
|---|---|
| Android 앱 ID | 빌드 인자 `-P admobAppId=ca-app-pub-…~…` |
| iOS 앱 ID | `ios/Flutter/Release.xcconfig`의 `ADMOB_APP_ID` |
| 배너 단위 ID | 빌드 인자 `--dart-define=BATON_AD_BANNER=ca-app-pub-…/…` (플랫폼별로 다름) |

릴리스에서 `BATON_AD_BANNER`가 비면 광고 요청과 동의 흐름을 아예 부르지 않음.
다만 Android SDK의 init provider는 광고 사용과 무관하게 앱 시작 때 매니페스트 앱 ID 형식을
검사하고 틀리면 앱을 죽임. 그래서 `admobAppId`는 비면 테스트 ID로 떨어지고, 형식이 틀리면 빌드가 실패함.
Android 앱 ID를 빠뜨리면 테스트 앱 ID로 나가 광고가 채워지지 않음.
대화상자·시트가 떠 있는 동안에는 배너를 배경막으로 덮어 바깥 탭이 광고로 가지 않게 함.

광고가 붙으면 기기 밖으로 나가는 데이터가 생기므로 스토어 신고가 필요함.
광고 ID, IP 주소(대략적 위치), 앱 상호작용, 진단 정보를 광고·분석 목적으로 수집·공유함.
Play는 Data safety와 Advertising ID·Contains ads 선언, App Store는 개인정보 라벨,
처리방침에는 AdMob 사용과 https://policies.google.com/technologies/partner-sites 링크가 들어감.
Android 병합 매니페스트에 `AD_ID`와 `ACCESS_ADSERVICES_*` 권한이 SDK로부터 자동으로 들어옴.

iOS는 ATT를 띄우지 않으므로 `NSUserTrackingUsageDescription`을 두지 않음.
AdMob 콘솔에서 IDFA 설명 메시지를 켜면 그 키와 AppTrackingTransparency 링크를 함께 추가해야 함.

## 출시 빌드

```sh
flutter build appbundle --release -P admobAppId=<Android 앱 ID> --dart-define=BATON_AD_BANNER=<Android 배너 단위>
flutter build ipa --release --dart-define=BATON_AD_BANNER=<iOS 배너 단위>
```

`BATON_API_BASE`를 붙이지 않음. v1은 AI 마디수 읽기를 빼고 내보내며, 주소가 비면
코인·AI 기능이 화면에서 통째로 숨음. 실수로 붙이면 서버 없는 앱에서 코인 UI가 켜져
등록 실패 오류가 뜸.

릴리스 서명이 아직 debug 키를 씀(`android/app/build.gradle.kts`). 업로드 전에 키스토어와
`android/key.properties`를 만들고 `signingConfigs`를 붙여야 Play가 받음.

## 개발

```sh
flutter test
flutter run -d <device-id>

python3 tool/gen_click.py          # 메트로놈 클릭 WAV 재생성
python3 tool/gen_fixtures.py       # 테스트용 이미지 재생성
python3 tool/gen_test_score.py     # 실기기 확인용 가짜 악보
python3 tool/analyze_drift.py LOG  # 클럭 드리프트 로그 분석
```

DB 스키마를 바꾸면 `dart run build_runner build`.

스키마를 올릴 때는 스냅샷을 먼저 뜸.

```sh
dart run drift_dev schema dump lib/core/db/database.dart drift_schemas/
```

`drift_schemas/`에 버전별 구조가 쌓임. `schemaVersion`을 올리면서 `onUpgrade`를 안 쓰면
drift 기본값이 예외를 던져 기존 사용자의 DB가 안 열리고 악보와 필기가 통째로 잠김.
스냅샷이 있어야 마이그레이션을 만들고 검증할 수 있음.
