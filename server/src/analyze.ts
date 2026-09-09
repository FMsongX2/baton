// 악보 페이지 이미지를 Claude 비전에 넘겨 페이지별 마디수와 템포를 뽑음.
// 앱의 barCount 정의(그 페이지가 화면에 떠 있는 동안 흐르는 마디 수)를 프롬프트에 그대로 박아 둠.
// 정의가 어긋나면 값이 그럴듯해 보여도 페이지 넘김이 밀림.

import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
// SDK의 zodOutputFormat이 zod/v4를 쓰므로 같은 진입점에서 가져와야 타입이 맞음
import * as z from 'zod/v4';
import type { Env } from './env.js';

/// 한 요청에 넣는 최대 페이지 수. 이미지가 많을수록 한 장에 쓰는 주의가 옅어져 나눠 보냄.
const PAGES_PER_REQUEST = 8;

/// 한 쪽이 가질 수 있는 최대 마디 수. 앱의 kMaxBarsPerPage와 같은 값.
const MAX_BARS_PER_PAGE = 999;

export const PageResultSchema = z.object({
  page: z.number().int(),
  bars: z.number().int(),
  confidence: z.enum(['high', 'medium', 'low']),
});

export const AnalysisSchema = z.object({
  pages: z.array(PageResultSchema),
  bpm: z.number().nullable(),
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
- ♩=120 처럼 숫자로 적힌 표기가 있으면 그 값을 쓰고 bpmSource를 marking으로 한다.
- 숫자 없이 Allegro, Andante 같은 말만 있으면 통용되는 중간값을 쓰고 tempo_word로 한다.
- 아무 표기도 없으면 bpm을 null, bpmSource를 none으로 둔다. 지어내지 않는다.

박자표는 첫 페이지에 적힌 것을 쓴다. 없으면 null로 둔다.`;

/// 페이지 묶음 하나를 분석함. 이미지 순서와 page 번호를 함께 넘겨 응답을 되짚을 수 있게 함.
async function analyzeChunk(client: Anthropic, pages: PageImage[]): Promise<Analysis> {
  const content: Anthropic.ContentBlockParam[] = [];
  for (const p of pages) {
    content.push({
      type: 'text',
      text: `${p.index + 1}쪽`,
    });
    content.push({
      type: 'image',
      source: { type: 'base64', media_type: p.mediaType, data: p.base64 },
    });
  }
  content.push({
    type: 'text',
    text: `위 ${pages.length}장의 악보에서 쪽마다 마디수를 세고, 템포와 박자표를 읽어라. page 값은 각 이미지 앞에 적힌 쪽 번호를 그대로 쓴다.`,
  });

  const response = await client.messages.parse({
    model: 'claude-opus-5',
    // adaptive thinking이 같은 예산을 함께 쓰므로 넉넉히 잡음.
    // 모자라면 stop_reason이 max_tokens가 되고 parsed_output이 비어 원인을 알기 어려움
    max_tokens: 16000,
    thinking: { type: 'adaptive' },
    system: SYSTEM,
    messages: [{ role: 'user', content }],
    output_config: { format: zodOutputFormat(AnalysisSchema) },
  });

  // 안전 분류기가 거절하면 200으로 오고 content가 비어 있으므로 먼저 확인함
  if (response.stop_reason === 'refusal') {
    throw new Error('모델이 이 이미지 분석을 거절함');
  }
  if (response.stop_reason === 'max_tokens') {
    throw new Error('응답이 길이 제한에 걸려 잘림');
  }
  const parsed = response.parsed_output;
  if (!parsed) throw new Error('분석 결과를 해석하지 못함');
  return parsed;
}

/// 악보 전체를 분석함. 페이지가 많으면 나눠 보내고 결과를 합침.
/// 템포·박자표는 앞쪽 묶음에서 먼저 읽힌 값을 남김. 보통 첫 페이지에만 적혀 있음.
export async function analyzeScore(env: Env, pages: PageImage[]): Promise<Analysis> {
  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });

  const merged: Analysis = {
    pages: [],
    bpm: null,
    bpmSource: 'none',
    timeSigNum: null,
    timeSigDen: null,
  };

  for (let i = 0; i < pages.length; i += PAGES_PER_REQUEST) {
    const chunk = pages.slice(i, i + PAGES_PER_REQUEST);
    const result = await analyzeChunk(client, chunk);
    merged.pages.push(...result.pages);
    if (merged.bpm === null && result.bpm !== null) {
      merged.bpm = result.bpm;
      merged.bpmSource = result.bpmSource;
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
  return merged;
}
