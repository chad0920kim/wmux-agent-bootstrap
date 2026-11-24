# 문제 해결

## 1. 설치/다운로드가 "인증서"나 "0x80072f0d" 오류로 실패해요

winget, gh, PowerShell 다운로드가 아래처럼 실패하는 경우입니다.

- `0x80072f0d`
- `SSL/TLS 보안 채널에 대한 트러스트 관계를 설정할 수 없습니다`
- `SEC_E_UNTRUSTED_ROOT`

**원인:** 이 PC에 Let's Encrypt 루트 인증서(`ISRG Root X1`)가 없고, 그룹 정책(`DisableRootAutoUpdate=1`)으로
Windows 루트 인증서 자동 갱신이 꺼져 있어서 GitHub 파일 서버(`release-assets.githubusercontent.com`) 인증서를 신뢰하지 못합니다.
`github.com` 자체와 `git push/pull`은 다른 인증 기관을 써서 정상일 수 있습니다.

### 가장 쉬운 방법
`시작하기.bat`을 실행하면, 설치 실패 시 자동으로 진단하고 **"지금 해결할까요?"** 라고 물어봅니다. `y`를 누르고 관리자 권한 창에서 "예"를 누르면 됩니다.

### 직접 하는 방법 (관리자 PowerShell)
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\skills\wmux-global-agents\scripts\fix-tls-root.ps1
Get-Content $env:TEMP\wmux-agent-bootstrap-tls-fix.log     # RESULT=OK 이면 성공
```
이 스크립트는 Microsoft 공식 루트 목록(`certutil -generateSSTFromWU`)에서 인증서를 가져와
**SHA-1 `CABD2A79A1076A31F21D253635CB039D4329A5E8` 과 SHA-256 `96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6` 이 모두 일치하고 자체 서명된 경우에만** `LocalMachine\Root`에 1개를 추가합니다.

### 회사/학교 PC라면
정책이 의도적으로 걸려 있을 수 있습니다. 먼저 IT 담당자에게 확인하세요.

### 되돌리기
```powershell
# 관리자 PowerShell
Get-ChildItem Cert:\LocalMachine\Root\CABD2A79A1076A31F21D253635CB039D4329A5E8 | Remove-Item
```

## 2. `시작하기.bat`을 눌렀더니 "Windows의 PC 보호" 창이 떠요
인터넷에서 받은 파일이라 나오는 정상 경고입니다. **추가 정보 → 실행**을 누르세요.
ZIP으로 받았다면 압축을 푼 뒤에 실행해야 합니다(압축 파일 안에서 바로 실행하면 안 돼요).

## 3. 새 탭에서도 `claude`/`grok`/`agy`가 안 잡혀요
- 설정 전에 열어 둔 탭은 옛 PATH를 갖고 있습니다. 새 탭을 열거나 `. $PROFILE.CurrentUserAllHosts`를 입력하세요.
- 그래도 안 되면 wmux를 완전히 종료했다가 다시 실행하세요.

## 4. 에이전트가 여전히 영어로 답해요
- 대화 중이던 에이전트는 시작할 때만 규칙 파일을 읽습니다. 껐다가 다시 실행하세요.
- 프로젝트 폴더에 자체 `CLAUDE.md` / `GEMINI.md`가 있으면 그 내용이 우선할 수 있습니다.

## 5. 실행 정책 오류 ("스크립트를 실행할 수 없습니다")
`시작하기.bat`은 실행 정책을 이번 실행에만 우회(`-ExecutionPolicy Bypass`)하므로 영향을 받지 않습니다.
`.ps1`을 직접 실행할 때만 발생하며, 그때도 `powershell -NoProfile -ExecutionPolicy Bypass -File <파일>` 형태로 실행하세요.

## 6. 변경을 모두 되돌리고 싶어요
`>>> wmux-agent-bootstrap:... >>>` 와 `<<< wmux-agent-bootstrap:... <<<` 사이 블록을 해당 파일
(`~/.claude/CLAUDE.md`, `~/.gemini/config/GEMINI.md`, `~/.grok/rules/language.md`, PowerShell 프로필)에서 지우세요.
백업은 `~/.wmux-agent-bootstrap/backups/<시각>/`에 있고, 이전 사용자 PATH는 같은 폴더의 `user-path.before.txt`에 있습니다.
