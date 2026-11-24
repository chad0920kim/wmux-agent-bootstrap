# wmux-agent-bootstrap

wmux를 처음 쓰는 Windows 사용자를 위한 초기 설정 도구입니다.
`claude`, `grok`, `agy`(Antigravity)를 **어느 폴더, 어느 wmux 탭에서든** 바로 실행할 수 있게 만들고,
원하면 모든 에이전트가 **항상 한국어로 답하도록** 전역 규칙을 한 번에 적용합니다.

*English: a one-shot setup tool for new wmux users on Windows — makes the agent CLIs callable from any folder / any wmux pane and (optionally) installs a global reply-language rule for every agent. Double-click `시작하기.bat`, or see [SKILL.md](skills/wmux-global-agents/SKILL.md) for LLM-driven use.*

---

## 🚀 처음 쓰는 분: 3단계면 끝

> 컴퓨터 지식이 없어도 됩니다. 명령어를 직접 입력할 필요가 없어요.

1. **다운로드** — 이 페이지 위쪽의 초록색 **`<> Code`** 버튼 → **Download ZIP**
2. **압축 풀기** — 받은 ZIP을 마우스 오른쪽 클릭 → **모두 압축 풀기** (⚠️ 압축 파일 안에서 바로 실행하면 안 돼요)
3. **`시작하기.bat` 더블클릭** — 화면에 나오는 질문에 번호나 `y`/`n`만 입력하세요.

도우미가 알아서 이렇게 진행합니다.

```
[1/4] 설치된 에이전트 찾기      → claude / grok / agy 가 있는지 확인 (없으면 Claude Code 설치를 도와줘요)
[2/4] 기본 응답 언어 고르기     → 1) 한국어  2) English  3) 건너뛰기
[3/4] 바뀔 내용 미리 보기       → 아직 아무것도 바꾸지 않아요
[4/4] 적용할까요? (y/n)         → y 를 눌러야만 바뀌어요
```

끝나면 **새 탭을 열어** 아무 폴더에서 `claude --version` 을 입력해 보세요. 버전이 나오면 성공입니다.

**안심하세요**
- 기존 내용은 지우지 않고 **추가만** 합니다. 바뀌는 파일은 자동으로 백업됩니다.
- 언제든 `n`을 누르면 아무것도 바뀌지 않아요. 같은 작업을 여러 번 실행해도 안전합니다.
- 막히면 [문제 해결](docs/TROUBLESHOOTING.md)을 보세요. (예: "PC 보호" 경고창, 인증서 오류 `0x80072f0d`)

> 💡 `시작하기.bat`을 처음 열 때 **"Windows의 PC 보호"** 창이 뜨면 정상입니다. **추가 정보 → 실행**을 누르세요.

---

## 무엇이 바뀌나

1. **사용자 PATH**에 에이전트 폴더 추가 (삭제·재정렬 없음)
2. **PowerShell 프로필**에 `Sync-AgentPath` 블록 추가 → 새 탭/패널이 항상 최신 PATH를 사용
3. 실행 정책이 `Restricted`일 때만 `CurrentUser`를 `RemoteSigned`로 (그룹 정책/AllSigned는 건드리지 않음)
4. 감지된 에이전트의 전역 규칙 파일에 언어 규칙 추가
   (`~/.claude/CLAUDE.md`, `~/.gemini/config/GEMINI.md`, `~/.grok/rules/language.md`)

모든 변경은 `~/.wmux-agent-bootstrap/backups/<시각>/`에 백업되며, `>>> wmux-agent-bootstrap` 마커 블록만 지우면 되돌아갑니다.

---

## 고급 사용자 / LLM으로 실행하기

### 에이전트에게 맡기기
1. 이 폴더로 이동해서 에이전트를 실행합니다. (`cd` 한 뒤 `claude` / `grok` / `agy`)
2. [`prompts/bootstrap.md`](prompts/bootstrap.md)의 프롬프트를 붙여넣습니다. (경로를 바꿀 필요 없어요)
3. 에이전트가 읽기 전용 검사 결과를 요약해 승인을 구하면 확인해 주세요.

Claude Code는 스킬로 등록하면 이름으로 바로 호출됩니다.
```powershell
Copy-Item -Recurse .\skills\wmux-global-agents $HOME\.claude\skills\
```

### 스크립트 직접 실행 (대화 없이)
```powershell
cd skills\wmux-global-agents\scripts
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko           # 검사만 (변경 없음)
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Language ko -Apply     # 적용
```
`-Language`는 `ko` / `en` / `none`, 직접 만든 규칙 파일은 `-RulesFile <경로>`, 기계가 읽기 쉬운 출력은 `-Json`.

### 이 스킬 자체도 LLM으로 실행됩니다 — 그래서 이렇게 만들었습니다

실제 작업은 **결정론적 스크립트**(`setup.ps1`)가 하고, LLM은 실행·해석·확인 요청만 맡습니다.

| LLM이 흔히 실패하는 지점 | 대응 |
|---|---|
| 기본 실행 정책(`Restricted`)에서 `.ps1`이 막히자 시스템 정책을 통째로 풀어버림 | `-ExecutionPolicy Bypass`를 **프로세스 한정**으로만 쓰도록 SKILL.md에 명시 |
| 기존 PATH/프로필/규칙 파일을 덮어씀 | **추가만** 하는 마커 블록, 수정 전 자동 백업 |
| 확인 없이 바로 시스템 변경 | 기본은 **읽기 전용 검사**, `-Apply`가 있어야만 변경. 적용 전 사용자 승인 필수 |
| 같은 작업을 반복·재시도 | 재실행해도 결과가 같은 **멱등성**, 오류 시 `nextAction`이 "멈추고 보고"를 지시 |
| 결과를 추측으로 "완료" 보고 | 새 셸을 **다른 폴더 + 최소 PATH**로 띄워 에이전트가 실제로 잡히는지 검증(`verify.allFound`) |
| 모델/에이전트마다 지침 해석이 다름 | 출력은 JSON + 명시적 `nextAction`, 지침은 짧은 명령형 |
| 에이전트 도구를 못 쓰는 상황 | LLM 없이 실행하는 `시작하기.bat` / 직접 실행 경로 제공 |

## 알려진 한계
- Windows PowerShell 5.1 / PowerShell 7 대상입니다 (Git Bash·WSL의 PATH는 별도).
- 이미 열려 있는 탭은 `. $PROFILE.CurrentUserAllHosts` 한 번 또는 새 탭이 필요하고, 이미 대화 중인 에이전트는 재시작해야 새 언어 규칙을 읽습니다.
- Grok·Antigravity의 전역 규칙 파일 위치는 2026-11 기준 버전(grok 1.0.x, agy 1.5.x)에서 확인한 값입니다. 바뀌면 `setup.ps1` 상단의 `$agentDefs`만 고치면 됩니다.
- 도우미가 직접 설치해 주는 에이전트는 Claude Code뿐입니다. Grok·Antigravity는 각 공식 안내대로 설치하세요.

## 구조
```
시작하기.bat                         더블클릭 진입점 (ASCII 전용)
skills/wmux-global-agents/
  SKILL.md                          LLM용 실행 지침 (Claude Code 스킬 형식)
  scripts/guide.ps1                 사람용 한국어 대화형 안내 (UTF-8 BOM)
  scripts/setup.ps1                 결정론적 설정 스크립트 (ASCII 전용, -Json)
  scripts/fix-tls-root.ps1          인증서 오류(0x80072f0d) 자동 해결 (관리자 권한)
  templates/rules.*.md              언어 규칙 원문 (UTF-8)
docs/TROUBLESHOOTING.md             문제 해결
prompts/bootstrap.md                에이전트에 붙여넣는 시작 프롬프트
AGENTS.md                           이 저장소를 수정하는 LLM용 안내
```

## 라이선스
MIT — [LICENSE](LICENSE)
