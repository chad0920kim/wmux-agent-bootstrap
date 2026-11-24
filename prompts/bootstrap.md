# 부트스트랩 프롬프트 (LLM 에이전트에 그대로 붙여넣기)

> 처음 쓰는 분은 이 파일 대신 저장소 맨 위의 **`시작하기.bat` 더블클릭**을 쓰세요. 이 프롬프트는 이미 에이전트(claude / grok / agy 중 아무거나)를 쓰는 분을 위한 것입니다.
>
> **사용법:** 이 저장소 폴더로 이동(`cd`)한 뒤 에이전트를 실행하고, 아래 프롬프트를 그대로 붙여넣으세요. 경로는 바꿀 필요가 없습니다.

## 한국어

```
현재 폴더의 wmux-global-agents 스킬을 실행해서, claude·grok·agy가 어느 폴더/어느 wmux 탭에서든 호출되게 설정해줘.

규칙:
1. 먼저 skills/wmux-global-agents/SKILL.md 를 끝까지 읽고 그 지침만 따른다. 스크립트를 수정하거나 단계를 임의로 바꾸지 않는다. (guide.ps1 은 사람용 대화형이라 쓰지 않고, setup.ps1 -Json 만 쓴다.)
2. 먼저 검사(읽기 전용)만 실행하고, 바뀔 내용을 쉬운 말로 요약해서 나에게 승인을 받은 뒤에만 -Apply 로 적용한다.
3. 기본 응답 언어 규칙은 나에게 한국어/영어/없음 중 무엇으로 할지 먼저 물어본다.
4. 인증 파일(토큰, API 키, oauth_creds.json 등)은 읽거나 출력하지 않는다.
5. 오류가 나면 반복 실행하지 말고, 결과를 보여주고 멈춘다.
```

## English

```
Run the wmux-global-agents skill in the current folder so that claude, grok and agy can be launched from any folder and any wmux tab.

Rules:
1. First read skills/wmux-global-agents/SKILL.md completely and follow only that. Do not edit the script or improvise steps. (Do not use guide.ps1 - it is the interactive version for humans; use setup.ps1 -Json only.)
2. Run the read-only check first, summarise the pending changes in plain words, and run with -Apply only after I approve.
3. Ask me whether the global reply-language rule should be Korean, English or none.
4. Never read or print credential files (tokens, API keys, oauth_creds.json, ...).
5. On any error do not retry in a loop: show me the result and stop.
```
