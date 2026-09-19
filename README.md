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
| `lib/metronome/clock.dart` | 재생 위치. 엔진 시각이 던지거나 멈추면 대체 시계로 물러섬 |
| `lib/metronome/audio_service.dart` | 오디오 엔진 수명과 세션 사건(인터럽트·출력 장치 해제) 전달 |
| `lib/metronome/click_scheduler.dart` | 룩어헤드 클릭 예약, 지연 보정 |
| `lib/core/db/` | drift 스키마와 저장소 |
| `lib/library/` | 폴더 트리. 목록은 drift 감시 쿼리로 그림 |
| `lib/core/progress_dialog.dart` | 뒤로가기로 닫히지 않고 끝나면 자기만 닫는 진행 대화상자 |
| `lib/reader/` | 뷰어·필기·자동 넘김 |
| `lib/reader/page_nav.dart` | 탭·페달이 가는 쪽과 스팬, 멈춘 동안 넘김의 재생 위치 계산 |
| `lib/reader/stage_layers.dart` | 넘김 탭 판정, 그리기 입력층, 무대 반전, 필압 정규화 |
| `lib/reader/annotation/stroke_store.dart` | 필기 캐시·되돌리기·저장 순서 |
| `lib/score/import/` | 가져오기 입구. 원천 사본 정리와 Android 유실 복구 |
| `lib/settings/pedal_keys.dart` | 페달 넘김 키 매핑. 기본값·학습 결과·화면 표시 이름 |
| `lib/billing/` | 메트로놈 언락(1회성)과 코인 묶음(소모성) 결제 |
| `lib/ads/ads.dart` | 광고 동의(UMP)·SDK 초기화와 앱 하단 배너 칸 |
| `lib/cloud/` | 서버 호출과 코인 지갑 |
| `lib/score/ai_analysis.dart` | AI가 읽은 마디수·템포를 반영하고 되돌림 |
| `server/` | Cloudflare Workers. OpenAI 키와 코인 원장을 여기에만 둠 |

임포트한 이미지·PDF는 입구에서 PDF 하나로 정규화함.
파일은 `<appDocuments>/scores/<nodeId>/source.pdf`에 두고 DB에는 상대경로만 저장함.
필기는 페이지 정규 좌표(0~1)로 저장해 원본 PDF를 건드리지 않음.

### 가져오기

가져오기마다 `<appDocuments>/import-staging/<pid>-<순번>/`에 PDF를 끝까지 쓰고 열리는지 확인한 뒤
DB 행을 만들고 `scores/<nodeId>/source.pdf`로 옮김. 남은 조각은 다음 가져오기가 치움.
JPEG가 아닌 이미지는 백그라운드 isolate에서 쪽마다 JPEG로 바꿈. iOS 스캐너도 JPEG로 받음.
여러 PDF 중 하나가 실패해도 나머지는 들임. 이름은 200자에서 자름.

끝나면(취소·실패 포함) 스캐너 저장소와 선택기 사본을 지움. Android에서 선택기·스캐너를 연 사이
Activity가 죽으면 다음 실행 때 라이브러리 루트가 이어서 들일지 물음. 가져오기·버리기 중 하나를
골라야 닫히고, 이름 입력을 닫거나 비우면 처음 물음으로 돌아감. 되찾은 사본은 버리기를 고르거나
가져오기를 끝까지 돌린 뒤에만 지움. 미뤄 둘 수는 없음. 스캔 사본은 다음 스캔이 끝날 때
cleanCache가 저장소째 지우기 때문. file_picker 선택은 복구하지 못함.

### 좌표계

pdfrx가 `pagePaintCallbacks`로 주는 `pageRect`는 확대·이동을 적용하기 전 **문서 좌표**임.
그리기 오버레이는 변환 밖에 있으므로 포인터 위치를 `PdfViewerController.globalToDocument`로
같은 계에 옮긴 뒤 정규화함. 화면 좌표를 그대로 쓰면 확대한 만큼 필기가 어긋난 자리에 저장됨.

### 일시정지와 재개

재개하면 멈춘 지점 앞의 마디선까지 되감고 그 구간을 카운트인으로 보여 줌.
되감은 구간의 클릭은 타임라인에 이미 있으므로 따로 만들지 않음.
마디선은 타임라인의 강박 클릭을 거꾸로 세어 찾으므로 앞 페이지의 템포·박자가 달라도 맞음.
카운트인 0마디로 두면 되감지 않고 멈춘 자리에서 이어감.

일시정지는 걸어 둔 클릭을 거두고 예약 커서를 멈춘 자리로 되돌림. 그래서 어느 재개 경로든
멈춘 자리 뒤 첫 클릭부터 울림. 지연 보정만큼 이미 출력으로 나간 클릭은 거둘 수 없어
재개 뒤 제자리에서 한 번 더 울림. `ClickScheduler.cancelPending`은 예약만 거두고 커서는 옮기지 않음.

시작·재개·건너뛰기는 기준점을 지연 보정+150ms 뒤에 잡음. 지금으로 잡으면 첫 강박의 예약 시각이
이미 지나 카운트인 첫 클릭이 버려짐. 그동안 위치는 음수이고 카운트인 숫자는 첫 클릭과 함께 뜸.
이 기준점 대기 중에 멈추면 대기가 향하던 위치에 멈춘 것으로 봄. 건너뛰기는 목표 쪽의 마디선에서
되감고, 재개 대기 중이면 같은 카운트인을 다시 셈. 소리 없이 멈춘 재개가 위치를 한 마디씩 물리지 않음.

멈춘 동안 탭·페달로 넘기면 재생 위치도 넘긴 방향에서 그 쪽을 연주하는 가장 가까운 회차의 처음으로
옮김. 그 위치가 첫 연주 쪽이면 곡의 처음(카운트인부터)으로 둠. 재생을 누르면 화면을 재생 위치의
쪽으로 다시 맞춤. 재생 중에는 처음으로·진행바·재생 설정을 막아 실수로 연주 위치를 잃지 않게 함.

### 0마디 쪽

표지처럼 연주가 없는 쪽은 재생 중 화면에 세우지 않음. 맨 앞 표지 대신 카운트인 동안 첫 연주 쪽을
보여 주고, 곡 중간의 빈 쪽은 앞 쪽의 선행 넘김이 다음 연주 쪽으로 바로 이어짐.
재생 중 이전·다음도 자동 넘김과 같은 이웃(`Timeline.playedNeighbor`)을 따라 0마디 쪽을 건너뜀.
앞뒤에 연주 쪽이 없으면 아무 일도 없어, 끝에 빈 쪽이 있어도 마지막 연주 쪽에서 다음을 눌러
재생이 멈추지 않음. 선행 넘김 뒤 이전(앞 쪽 다시 보기)도 0마디를 건너뛴 앞 연주 쪽을 보여 줌.
카운트인은 첫 연주 쪽의 템포·박으로 셈. 맨 앞 표지 값은 쓰지 않음.

멈춘 동안에는 넘겨서 볼 수 있음. 그동안 재생 위치는 연주 순서상 다음 연주 쪽의 처음에 둠.
끝의 빈 쪽에 서는 것은 진행바와 멈춘 상태의 직접 선택뿐.

### 오디오 세션

iOS는 AppDelegate가 시작 때 세션을 playback+mixWithOthers로 정하고, 광고 SDK 등이 바꾸면 되돌림.
무음 스위치와 무관하게 클릭이 들리고 반주 앱과 함께 울림. Android는 오디오 포커스를 잡지 않음.

전화 같은 인터럽트, 이어폰·블루투스 해제(iOS oldDeviceUnavailable, Android BECOMING_NOISY)는
EventChannel `baton/audio_session`으로 들어와 리더와 메트로놈을 멈춤. 자동으로 다시 틀지 않음.

엔진 시각이 500ms 넘게 그대로면 출력 장치가 멈춘 것으로 보고 대체 시계로 물러서 넘김을 이어 감.
그 재생 동안 클릭은 멈춤. 다음 재생 시작 때 무음 재생으로 장치를 깨워 다시 엔진 시각을 따름.

지연 보정은 0~400ms로 접음. 예약 창을 룩어헤드+지연 보정으로 잡아 보정이 커도 클릭이 빠지지 않음.

### 리더 조작

넘김 탭은 제스처 경합 없이 포인터로 판정해 떼는 즉시 넘김. 빠른 연속 탭은 탭 수만큼 넘김.
맨 위 띠는 지금 쪽의 넘김까지 진행을 보여 주고, 넘김 한 마디 전부터 굵어지며 색이 바뀜.
앞뒤 쪽은 0마디를 건너뛴 이웃으로 세므로 오지 않을 넘김(끝 빈 쪽 앞)은 예고하지 않음.

터치 잠금은 좌우 탭 넘김·드래그·확대와 위치를 바꾸는 버튼을 막고 페달·재생·잠금 해제는 받음.
설정 키 `reader_lock`에 저장해 곡을 바꿔도 유지함. 그리는 동안은 잠금을 멈추고 알림.

반전은 전용 렌더 객체가 켜졌을 때만 색 필터 레이어를 씌움. 트리 모양이 같아 뷰어의 쪽·배율이
유지되고, 꺼져 있을 때는 합성 레이어를 만들지 않음.

필기 캐시는 PDF가 바뀐 경우(회전)에만 버림. 저장은 그 쪽 필기를 다 읽은 뒤의 목록을 씀.
먼저 쓰면 DB에 있던 획을 방금 그린 획으로 덮어씀. 필압은 펜만 0~1로 정규화해 저장함.

폴더 화면과 리더는 복원 가능한 경로로 열려, 프로세스가 죽었다 살아나도 보던 폴더·악보·재생 위치로
돌아옴. 경로 빌더는 `@pragma('vm:entry-point')`가 붙은 static 함수여야 릴리스(AOT)에서 다시 찾음.

### 코인 소유권

서버가 발급한 토큰이 곧 코인 소유권임. 앱 DB(`baton.sqlite`)가 아니라 `device.json`에 따로 둠.
백업 zip은 `baton.sqlite`와 `scores/`만 담으므로, 백업을 남에게 넘겨도 코인은 넘어가지 않음.
기기를 바꿀 때는 복구 코드로 옮김.

복구 코드는 서버가 해시만 들고 있어 이미 발급한 것을 다시 보여 줄 수 없음.
새 코드는 대기 상태로 받고(`POST /v1/device/recovery`), '적어 뒀음'으로 확인해야
(`POST /v1/device/recovery/confirm`) 이전 코드가 무효가 됨. 응답이 유실돼도 옛 코드가 살아 있음.
입력은 대시·공백·대소문자를 무시함. 가져오기 전에 이 기기에 남은 코인이 버려지면 먼저 경고함.

### 백업

`baton.sqlite`와 `scores/`를 zip 하나로 묶음. 되살리기는 합치기가 아니라 교체.
zip은 `baton.sqlite`와 `scores/<숫자>/` 아래만 받고 나머지는 거부함. DB에 담긴 `fileRel`도
`AppPaths.abs`가 앱 디렉토리 기준으로 검사함. 백업은 남이 만든 것일 수 있음.

zip을 `restore-staging`에 끝까지 푼 뒤 DB를 검사함(SQLite 여부, quick_check, user_version이
1 이상이고 앱 schemaVersion 이하). 통과해야 DB를 닫고 이름 바꾸기로 교체함.
교체하는 동안 `restore.journal`을 남기고, 앱 시작 때 DB를 열기 전에 끝나지 않은 교체를
`pre-restore` 사본으로 되돌림. 저널이 남아 있으면 되살리기를 거부함. 그 사본이 유일한 원본이기 때문.

지금 DB가 열리지 않아도(손상, 더 새 schemaVersion) 되살리기로 교체함. 되살리기가 복구 수단이기 때문.
교체 전에 WAL을 체크포인트하지 않고 `baton.sqlite`와 짝 파일(-wal, -shm, -journal)을 한 묶음으로
`baton.sqlite.pre-restore*`로 밀어 두고 되돌릴 때도 묶음으로 돌림. 옛 WAL이 새 DB 옆에 남으면
SQLite가 새 DB에 덮어 씀. DB 닫기부터 실패하면 풀어 둔 staging을 지우고 재시작을 요구함.

기기마다 다른 설정(`kDeviceLocalKeys`: 출력 지연 보정, 메트로놈 구매 캐시)은 백업 값 대신
이 기기 값을 남김. 지금 DB를 읽지 못하면 백업 값을 들이지 않고 기본값으로 둠.
구매 캐시는 백업으로 옮겨지지 않으므로 새 기기는 스토어 확인이나 '구매 복원'으로 풀림.

### 삭제

삭제는 `deletedAt`만 찍고 파일은 두며, 휴지통에서 영구 삭제하거나 30일이 지나면
앱을 열 때 파일까지 함께 사라짐(`LibraryRepo.purge` / `purgeExpired`).
`deletedAt`은 drift 규칙대로 초 단위로 저장함.
purge는 휴지통에 든 노드만 지우고, 그 밑에 섞인 살아 있는 노드는 루트로 올려 파일을 남김.
휴지통에 든 폴더 안에는 만들거나 옮기지 못하고, 폴더 화면은 자기 폴더가 휴지통으로 가면 닫힘.

### 라이브러리 목록

drift 감시 쿼리로 그려 어느 화면에서 바꾸든 반영됨. 파일만 바뀌는 경우(가져오기 완료, 회전)는
`LibraryRepo.touch`로 updatedAt을 올려 알림. 칸은 노드 id로 키를 달고 updatedAt이 바뀌면 표지를
다시 찾음. 표지는 임시 파일에 쓴 뒤 rename해 반쯤 쓰인 그림이 보이지 않음.
이름은 자연 정렬(숫자 크기, 대소문자 무시)함.

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

요청마다 `requestId`(`<묶음 id>-<쪽 번호들>`)를 실어 보냄. 결과를 못 받은 실패(끊김, 시간 초과,
409, 500/503/504)는 같은 id로 다시 보냄. 묶음 id는 악보별 설정 `ai_batch_<scoreId>`에 두고
끝까지 받으면 지움. 서버는 id를 코인 차감 전에 사용자별로 선점해 두 번 빠지거나 두 번 환불되지 않고,
이미 끝난 분석이면 저장해 둔 결과를 그대로 돌려줌. 모델이 빠뜨린 쪽은 그 몫만큼 돌려줌.

서버의 모델 호출은 요청 하나당 210초 한도로 묶고 재시도도 그 안에 넣음. 한도에 걸리거나 모델이
시간 초과로 답하면 같은 요청을 다시 보내지 않고 502로 전액 환불함. 선점 기한은 4분.
앱의 요청 한도는 5분(서버 한도에 이미지 올리는 시간을 더함). 한도와 사용자 멈춤은 기다림만 끝내고
연결은 닫지 않아, 서버가 끝까지 돌고 결과를 남기며 같은 id 재전송이 그 결과를 받음.

분석 중에는 '취소'로 멈출 수 있고, 뒤로가기는 분석을 멈춘 뒤 화면을 닫음. 멈추면 받은 결과도
반영하지 않고 묶음 기록을 남겨, 다시 누르면 같은 id로 코인 없이 이어받음. 묶음 기록에는
보낸 쪽(sent)과 결과 받은 쪽(answered)을 두고, 확인 대화상자는 이미 결제된 쪽을 빼고 비용을 보임.

템포는 숫자 표기만 반영하고, 표기 음표 단위(bpmUnit)를 앱 클릭 단위로 환산함
(2/2 ♩=144→72, 6/8 ♪=168→56). 단위를 모르거나 20~400 밖이면 비워 둠.

### 서버 준비

```sh
cd server
npm install
npx wrangler d1 create baton          # 나온 database_id를 wrangler.toml에 채움
npm run db:init                       # 스키마 적용
npx wrangler secret put OPENAI_API_KEY
npm run deploy
```

서버 테스트는 `cd server && npm test`(Node 22.18+의 node:test·node:sqlite).
스키마가 바뀌면(users.pending_recovery_hash, analyses의 PK·선점 열) 로컬 D1은 다시 만듦.

영수증 검증을 붙이기 전에는 `BLOCK_UNVERIFIED_PURCHASES=1`이라 코인 적립이 막혀 있음.
`server/src/receipts.ts`의 verifyPurchase를 채우고 값을 `0`으로 바꿔야 실제 결제가 동작함.

스토어에는 비소모성 `baton_metronome`과 소모성 `baton_coins_10` / `_60` / `_150`을 등록함.
지급 코인 수는 `server/src/receipts.ts`의 COIN_PACKS가 정함.

코인 구매는 서버 적립을 확인한 뒤에만 소비함(Android 자동 소비 끔, iOS는 적립 뒤 finish).
적립하지 못한 구매는 앱 복귀, 잔액 새로고침, 같은 묶음 재구매 때 다시 적립함.

### 앱에 서버 주소 넣기

```sh
flutter run --dart-define=BATON_API_BASE=https://baton-server.<계정>.workers.dev
```

주소가 비면 코인과 AI 기능이 화면에서 숨음. 나머지 기능은 그대로 동작함.

## 언어

한국어 전용 앱. supportedLocales를 ko 하나로 두어 기기 언어와 무관하게 Material·Cupertino
기본 문구가 한국어로 나옴. iOS는 Info.plist의 CFBundleLocalizations=[ko]와
CFBundleDevelopmentRegion=ko로 문서 선택기·공유 시트·스캐너 같은 시스템 UI도 한국어로 띄움.

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
