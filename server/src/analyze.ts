// 악보 페이지 이미지를 GPT 비전에 넘겨 페이지별 마디수와 템포를 뽑음.
// 앱의 barCount 정의(그 페이지가 화면에 떠 있는 동안 흐르는 마디 수)를 프롬프트에 그대로 박아 둠.
// 정의가 어긋나면 값이 그럴듯해 보여도 페이지 넘김이 밀림.

import OpenAI from 'openai';
import { zodTextFormat } from 'openai/helpers/zod';
// 서버 전체가 같은 zod 진입점을 씀. zodTextFormat은 v3·v4 스키마를 모두 받음
import * as z from 'zod/v4';
import { analysisModel, type Env } from './env.js';

/// 한 요청에 넣는 최대 페이지 수. 이미지가 많을수록 한 장에 쓰는 주의가 옅어져 나눠 보냄.
const PAGES_PER_REQUEST = 8;

/// 한 쪽이 가질 수 있는 최대 마디 수. 앱의 kMaxBarsPerPage와 같은 값.
const MAX_BARS_PER_PAGE = 999;

/// 분석 요청 하나가 모델 호출에 쓰는 시간 전체(재시도 포함). 한 번 호출에 거의 다 쓸 수 있게 둠.
/// analyses.ts의 ANALYSIS_LEASE_MS(4분) 안에 결과 기록까지 마치도록 30초를 남기고,
/// 앱의 kAnalyzeTimeout(5분)에는 이미지를 올리는 시간을 남김. 앱의 한도·취소는 기다림만 끝내고
/// 연결을 닫지 않아 워커는 끝까지 돌고 결과를 남김. 연결이 실제로 끊기면(네트워크 단절·앱 종료)
/// 워커가 취소돼, 선점 기한 뒤의 재전송이 모델을 다시 부름.
export const ANALYSIS_BUDGET_MS = 210_000;

/// 한도 안에서 같은 요청을 다시 보내는 횟수. 대상은 SDK 규칙(409·429·5xx·연결 오류,
/// x-should-retry: true)에서 시간 초과 응답을 뺀 것. 한도나 시간 초과로 끊긴 호출은
/// 모델이 이미 읽었을 수 있어 다시 보내면 토큰을 두 번 씀.
const OPENAI_MAX_RETRIES = 1;

/// 시간 초과 응답. 408은 요청 시간 초과, 504·524는 앞단이 모델 응답을 기다리다 끊은 것.
const TIMEOUT_STATUSES = new Set([408, 504, 524]);

/// 모델 서버 호출. 시간 초과 응답에 x-should-retry: false를 붙여 SDK가 다시 보내지 않게 함.
async function fetchWithoutTimeoutRetry(
  input: string | URL | Request,
  init?: RequestInit,
): Promise<Response> {
  const res = await fetch(input, init);
  if (!TIMEOUT_STATUSES.has(res.status)) return res;
  const headers = new Headers(res.headers);
  headers.set('x-should-retry', 'false');
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}

export const PageResultSchema = z.object({
  page: z.number().int(),
  bars: z.number().int(),
  confidence: z.enum(['high', 'medium', 'low']),
});

/// 템포 표기의 음표 단위. 앱이 박자표로 정한 클릭 음표와 길이가 다르면 앱이 환산함.
export const BpmUnitSchema = z.enum([
  'whole',
  'dotted_half',
  'half',
  'dotted_quarter',
  'quarter',
  'dotted_eighth',
  'eighth',
  'sixteenth',
]);

export const AnalysisSchema = z.object({
  pages: z.array(PageResultSchema),
  bpm: z.number().nullable(),
  bpmUnit: BpmUnitSchema.nullable(),
  bpmSource: z.enum(['marking', 'tempo_word', 'none']),
  timeSigNum: z.number().int().nullable(),
  timeSigDen: z.number().int().nullable(),
});

export type Analysis = z.infer<typeof AnalysisSchema>;

export interface PageImage {
  index: number;
  mediaType: 'image/png' | 'image/jpeg';
  base64: string;
}

const SYSTEM = `너는 악보를 읽어 연주 진행에 필요한 수치를 뽑는 도구다. 설명하지 말고 요청된 값만 낸다.

마디수 세는 규칙:
- 세로 마디선으로 나뉜 칸의 개수를 센다. 한 페이지의 모든 단을 합산한다.
- 피아노 대보표처럼 위아래 두 줄이 하나로 묶인 경우 그 둘은 한 마디다. 두 번 세지 않는다.
- 못갖춘마디(앞머리의 짧은 마디)는 한 마디로 센다.
- 페이지 안에서 도돌이표로 되풀이되는 구간은 되풀이되는 횟수만큼 더해서 센다.
  이 값은 "악보에 그려진 마디 칸 수"가 아니라 "그 페이지를 보는 동안 실제로 흐르는 마디 수"다.
- 겹세로줄과 끝세로줄은 마디를 나누는 선일 뿐 그 자체가 마디가 아니다.
- 확신이 서지 않으면 confidence를 낮춘다. 억지로 맞추지 않는다.

템포:
- ♩=120 처럼 숫자로 적힌 표기가 있으면 그 숫자를 bpm에, 등호 왼쪽 음표를 bpmUnit에 쓰고 bpmSource를 marking으로 한다.
  bpmUnit은 온음표 whole, 점2분음표 dotted_half, 2분음표 half, 점4분음표 dotted_quarter, 4분음표 quarter,
  점8분음표 dotted_eighth, 8분음표 eighth, 16분음표 sixteenth 중 하나다. 음표를 읽지 못하면 bpmUnit을 null로 둔다.
- 숫자 없이 Allegro, Andante 같은 말만 있으면 bpm과 bpmUnit을 null, bpmSource를 tempo_word로 둔다. 값을 추정하지 않는다.
- 아무 표기도 없으면 bpm과 bpmUnit을 null, bpmSource를 none으로 둔다. 지어내지 않는다.

박자표는 첫 페이지에 적힌 것을 쓴다. 없으면 null로 둔다.`;

/// 페이지 묶음 하나를 분석함. signal이 끊으면 재시도 없이 실패함.
async function analyzeChunk(
  client: OpenAI,
  model: string,
  pages: PageImage[],
  signal: AbortSignal,
): Promise<Analysis> {
  // 이미지 순서와 page 번호를 함께 넘겨 응답을 되짚을 수 있게 함
  const content: OpenAI.Responses.ResponseInputMessageContentList = [];
  for (const p of pages) {
    content.push({ type: 'input_text', text: `${p.index + 1}쪽` });
    content.push({
      type: 'input_image',
      // 마디선은 한 픽셀짜리 세로선이라 축소되면 뭉개짐. auto로 두면 긴 변이 줄어 단을 못 셈
      detail: 'high',
      image_url: `data:${p.mediaType};base64,${p.base64}`,
    });
  }
  content.push({
    type: 'input_text',
    text: `위 ${pages.length}장의 악보에서 쪽마다 마디수를 세고, 템포와 박자표를 읽어라. page 값은 각 이미지 앞에 적힌 쪽 번호를 그대로 쓴다.`,
  });

  const response = await client.responses.parse(
    {
      model,
      instructions: SYSTEM,
      input: [{ role: 'user', content }],
      // 추론 토큰이 같은 예산을 함께 쓰므로 넉넉히 잡음.
      // 모자라면 status가 incomplete가 되고 output_parsed가 비어 원인을 알기 어려움
      max_output_tokens: 16000,
      reasoning: { effort: 'medium' },
      text: { format: zodTextFormat(AnalysisSchema, 'analysis') },
    },
    { signal },
  );

  // 안전 분류기가 거절하면 200으로 오고 본문 대신 refusal이 실리므로 먼저 확인함
  for (const item of response.output) {
    if (item.type !== 'message') continue;
    if (item.content.some((c) => c.type === 'refusal')) {
      throw new Error('모델이 이 이미지 분석을 거절함');
    }
  }
  if (response.status === 'incomplete') {
    const reason = response.incomplete_details?.reason;
    throw new Error(
      reason === 'max_output_tokens'
        ? '응답이 길이 제한에 걸려 잘림'
        : `응답이 중간에 끊김: ${reason ?? '알 수 없음'}`,
    );
  }
  const parsed = response.output_parsed;
  if (!parsed) throw new Error('분석 결과를 해석하지 못함');
  return parsed;
}

/// 악보 전체를 budgetMs 안에 분석함. 넘기거나 시간 초과 응답이 오면 재시도 없이 실패함.
export async function analyzeScore(
  env: Env,
  pages: PageImage[],
  budgetMs = ANALYSIS_BUDGET_MS,
): Promise<Analysis> {
  // 한도는 호출마다가 아니라 요청 전체에 신호로 검. SDK 자체 한도(timeout)로 끊기면 SDK가
  // 같은 요청을 다시 보내지만, 호출자 신호로 끊긴 호출은 다시 보내지 않음.
  // SDK 한도는 기본값(10분)으로 둬 신호보다 먼저 걸리지 않게 함
  const signal = AbortSignal.timeout(budgetMs);
  const client = new OpenAI({
    apiKey: env.OPENAI_API_KEY,
    maxRetries: OPENAI_MAX_RETRIES,
    fetch: fetchWithoutTimeoutRetry,
  });
  const model = analysisModel(env);

  const merged: Analysis = {
    pages: [],
    bpm: null,
    bpmUnit: null,
    bpmSource: 'none',
    timeSigNum: null,
    timeSigDen: null,
  };

  for (let i = 0; i < pages.length; i += PAGES_PER_REQUEST) {
    const chunk = pages.slice(i, i + PAGES_PER_REQUEST);
    const result = await analyzeChunk(client, model, chunk, signal);
    merged.pages.push(...result.pages);
    // 템포는 숫자 표기(marking)를 앞쪽 묶음부터 찾아 남기고, 용어만 있으면 수치 없이 출처만 남김.
    // 박자표는 앞쪽 묶음에서 먼저 읽힌 값을 남김. 보통 첫 페이지에만 적혀 있음
    if (merged.bpmSource !== 'marking' && result.bpmSource === 'marking' && result.bpm !== null) {
      merged.bpm = result.bpm;
      merged.bpmUnit = result.bpmUnit;
      merged.bpmSource = 'marking';
    } else if (merged.bpmSource === 'none' && result.bpmSource === 'tempo_word') {
      merged.bpmSource = 'tempo_word';
    }
    if (merged.timeSigNum === null && result.timeSigNum !== null) {
      merged.timeSigNum = result.timeSigNum;
      merged.timeSigDen = result.timeSigDen;
    }
  }

  // 모델이 요청에 없던 쪽 번호나 터무니없는 마디수를 돌려줄 수 있음.
  // 앱까지 흘려보내면 재생이 몇 시간짜리가 되거나 반영 집계가 부풀려짐
  const requested = new Set(pages.map((p) => p.index + 1));
  const seen = new Set<number>();
  merged.pages = merged.pages
    .filter((p) => requested.has(p.page) && !seen.has(p.page) && seen.add(p.page))
    .map((p) => ({ ...p, bars: Math.min(Math.max(Math.trunc(p.bars), 0), MAX_BARS_PER_PAGE) }));

  merged.pages.sort((a, b) => a.page - b.page);
  // 숫자 표기가 아니면 수치를 내보내지 않음. 모델이 지시를 어기고 추정값을 넣어도 앱까지 흘리지 않음
  if (merged.bpmSource !== 'marking') {
    merged.bpm = null;
    merged.bpmUnit = null;
  }
  return merged;
}
