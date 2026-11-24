# wmux-agent-bootstrap

wmux를 처음 쓰는 Windows 사용자를 위한 초기 설정 스킬입니다.
`claude`, `grok`, `agy`(Antigravity), `wmux`를 **어느 폴더, 어느 wmux 탭에서든** 바로 호출할 수 있게 만들고,
원하면 모든 에이전트에 **전역 응답 언어 규칙**(예: 항상 한국어)을 한 번에 적용합니다.

*English: a one-shot setup skill for new wmux users on Windows — makes the agent CLIs callable from any folder / any
wmux pane and (optionally) installs a global reply-language rule for every agent. See [SKILL.md](skills/wmux-global-agents/SKILL.md).*

## 이 스킬 자체도 LLM으로 실행됩니다 — 그래서 이렇게 만들었습니다

스킬은 LLM이 실행하지만, 실제 작업은 **결정론적 스크립트 하나**(`setup.ps1`)가 합니다. LLM은 실행·해석·확인 요청만 맡습니다.

| LLM이 흔히 실패하는 지점 | 대응 |
|---|---|
| 기본 실행 정책(`Restricted`)에서 `.ps1`이 막히자 시스템 정책을 통째로 풀어버림 | `-ExecutionPolicy Bypass`를 **프로세스 한정**으로만 쓰도록 SKILL.md에 명시 |
| 기존 PATH/프로필/규칙 파일을 덮어씀 | **추가만** 하는 마커 블록(`>>> wmux-agent-bootstrap`), 수정 전 자동 백업 |
| 확인 없이 바로 시스템 변경 | 기본은 **읽기 전용 검사**, `-Apply`가 있어야만 변경. 적용 전 사용자 승인 필수 |
| 같은 작업을 반복·재시도 | 재실행해도 결과가 같은 **멱등성**, 오류 시 `nextAction`이 "멈추고 보고"를 지시 |
| 결과를 추측으로 "완료" 보고 | 새 셸을 **다른 폴더 + 최소 PATH**로 띄워 에이전트가 실제로 잡히는지 검증(`verify.allFound`) |
| 모델/에이전트마다 지침 해석이 다름 | 출력은 JSON + 명시적 `nextAction`, 지침은 짧은 명령형 |
| 에이전트 도구를 못 쓰는 상황 | LLM 없이 직접 실행하는 경로 제공(아래) |

## 사용법

### A. 이미 에이전트(claude/grok/agy)가 하나라도 설치돼 있을 때 — 가장 쉬움
1. 이 저장소를 받습니다.
   ```powershell
   git clone <이 저장소 URL> $HOME\wmux-agent-bootstrap
   ```
2. 에이전트를 열고 [`prompts/bootstrap.md`](prompts/bootstrap.md)의 프롬프트를 붙여넣습니다(저장소 경로만 바꾸기).
3. 에이전트가 검사 결과를 요약해 승인을 구하면 확인해 주세요.

Claude Code는 스킬로 등록하면 이름으로 바로 호출됩니다.
```powershell
Copy-Item -Recurse $HOME\wmux-agent-bootstrap\skills\wmux-global-agents $HOME\.claude\skills\
```

### B. LLM 없이 직접 실행
```powershell
cd $HOME\wmux-agent-bootstrap\skills\wmux-global-agents\scripts
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko           # 검사만 (변경 없음)
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko -Apply     # 적용
```
`-Language`는 `ko` / `en` / `none`. 직접 만든 규칙 파일은 `-RulesFile <경로>`.

## 무엇이 바뀌나

1. **사용자 PATH**에 에이전트 폴더 추가(삭제·재정렬 없음)
2. **PowerShell 프로필**에 `Sync-AgentPath` 블록 추가 → 새 탭/패널이 항상 최신 PATH를 사용
3. 실행 정책이 `Restricted`일 때만 `CurrentUser`를 `RemoteSigned`로(그룹 정책/AllSigned는 건드리지 않음)
4. 감지된 에이전트의 전역 규칙 파일에 언어 규칙 블록 추가
   (`~/.claude/CLAUDE.md`, `~/.gemini/config/GEMINI.md`, `~/.grok/rules/language.md`)

모든 변경은 `~/.wmux-agent-bootstrap/backups/<시각>/`에 백업되며, 마커 블록만 지우면 되돌아갑니다.

## 알려진 한계
- Windows PowerShell 5.1 / PowerShell 7 대상입니다(Git Bash·WSL의 PATH는 별도).
- 이미 열려 있는 탭은 `. $PROFILE.CurrentUserAllHosts` 한 번 또는 새 탭이 필요하고, 이미 대화 중인 에이전트는 재시작해야 새 언어 규칙을 읽습니다.
- Grok·Antigravity의 전역 규칙 파일 위치는 2026-11 기준 버전(grok 1.0.x, agy 1.5.x)에서 확인한 값입니다. 바뀌면 `setup.ps1` 상단의 `$agentDefs`만 고치면 됩니다.

## 구조
```
skills/wmux-global-agents/
  SKILL.md              LLM용 실행 지침 (Claude Code 스킬 형식)
  scripts/setup.ps1     결정론적 설정 스크립트 (ASCII 전용)
  templates/rules.*.md  언어 규칙 원문 (UTF-8)
prompts/bootstrap.md    아무 에이전트에 붙여넣는 시작 프롬프트
AGENTS.md               이 저장소를 수정하는 LLM용 안내
```
