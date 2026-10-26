# Chack! · 월간 가계부 (소스 · 비공개)

서버 없이 **내 맥과 내 iCloud Drive에만** 저장하는 개인 가계부 맥 앱의 소스예요.
설치 파일과 업데이트는 공개 저장소 **[joukey123/chack-release](https://github.com/joukey123/chack-release)** 에서 배포해요.

## 새 버전 내는 법

1. 코드를 고쳐 main에 올려요. → `build` 워크플로가 검사·빌드·DMG 실행 확인을 해요.
2. `version.json`의 `version`과 `notes`를 바꿔 main에 올려요.
3. `release` 워크플로가 애플 실리콘·인텔 DMG를 만들어 chack-release에 `v버전` Release로 올려요.
4. 설치된 앱은 설정 › 업데이트 확인에서 새 버전을 찾아 자동으로 바꿔 끼워요.

필요한 비밀값: `RELEASE_TOKEN` — chack-release 저장소에 **Contents: Read and write** 권한이 있는 fine-grained 토큰.

## 구성

```
Sources/              SwiftUI 앱 (swiftc로 바로 컴파일, Xcode 프로젝트 없음)
Tests/main.swift      계산 규칙 검사
Resources/            앱 아이콘(AppIcon.png), 사이드바 표시(Mark.png), 글꼴(SIL OFL)
scripts/build-app.sh  arm64 | x86_64 앱 번들 빌드 → dist/<arch>/Chack!.app
scripts/make-dmg.sh   arm64 | x86_64 → dist/Chack-AppleSilicon.dmg | dist/Chack-Intel.dmg
build.sh              개발용: 이 맥에서 빌드해 바로 /Applications에 설치
```

## 저장 방식

- 기본 위치: `iCloud Drive/Chack/가계부.json` (예전 이름 `차곡` 폴더에 가계부가 있으면 그대로 사용)
- 저장할 때마다 `백업/`에 1시간 단위 사본 (최근 72개)
- 맥·아이폰이 같은 파일을 써도 수정 시각·삭제 기록으로 합쳐서 저장
- 번들 ID `com.joukey123.chack` (예전 `com.joukey123.chagok`의 저장 위치 설정을 이어받음)
