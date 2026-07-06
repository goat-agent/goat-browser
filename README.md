# Goat Browser

네이티브 macOS 브라우저 (Chromium 임베드, Swift + SwiftUI/AppKit).

## 빌드

```sh
scripts/fetch-cef.sh      # CEF Standard 배포 다운로드 + sha1 검증 + framework/wrapper 배치
scripts/build-wrapper.sh  # libcef_dll_wrapper.a 빌드
xcodegen generate         # project.yml -> GoatBrowser.xcodeproj
xcodebuild -project GoatBrowser.xcodeproj -scheme GoatBrowser \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/build" build
scripts/smoke.sh          # 앱 실행 + CDP(9222)로 example.com 렌더 검증 (PASS/FAIL)
```

## 부트스트랩 메모 (CEF 임베드)

- **샌드박스 OFF** (`no_sandbox=true`, `cef_sandbox` 링크 안 함) — 초기 브링업 단순화.
- **외부 메시지 펌프**: `CefSettings.external_message_pump=true` +
  `CefBrowserProcessHandler::OnScheduleMessagePumpWork`. CEF 공유 샘플
  (`tests/shared/browser/main_message_loop*.{cc,h}`,
  `main_message_loop_external_pump*.{cc,h,mm}`)를 `project.yml`에서 직접 참조해
  앱 타깃 소스로 추가. SwiftUI가 `NSApp run`을 소유하므로 펌프의 `Run()`은 호출하지
  않고, `OnScheduleMessagePumpWork`가 NSTimer로 메인 런루프에 `CefDoMessageLoopWork()`를
  스케줄하는 부분만 사용.
- **네이티브 호스팅**: `GoatBrowserContainerView`(NSView)를 단일 안정 컨테이너로 두고
  `CefWindowInfo::SetAsChild`(windowed rendering)로 CEF 브라우저를 자식으로 붙임.
  SwiftUI에는 `NSViewRepresentable`로 한 번만 호스팅(매 diff마다 reparent 안 함).
- **CefAppProtocol/SwiftUI 충돌 해결**: SwiftUI가 자체 NSApplication 서브클래스
  (`SwiftUI.AppKitApplication`)를 설치하고 `NSPrincipalClass`를 무시하므로, 런타임에
  `[NSApp class]`에 `isHandlingSendEvent`/`setHandlingSendEvent:`를 추가하고
  `sendEvent:`를 swizzle, `CefAppProtocol` 적합성을 `class_addProtocol`로 선언
  (`Bridge/GoatCEF.mm`).
- **번들 구조**: 메인 앱 + `Chromium Embedded Framework.framework` +
  5개 헬퍼 앱(`Goat Browser Helper[ (Alerts)/(GPU)/(Plugin)/(Renderer)].app`)를
  `Contents/Frameworks`에 배치. 빌드 단계(run script)로 프레임워크 복사 →
  헬퍼 복사 → inside-out ad-hoc 코드서명.
- **프레임워크 링크**: CEF 프레임워크는 직접 링크하지 않고 런타임에
  `CefScopedLibraryLoader`로 dlopen. 실행 파일은 `libcef_dll_wrapper.a` +
  AppKit/Cocoa/IOSurface만 링크 (cefsimple과 동일).

## 구조

- `scripts/` — CEF 다운로드(`fetch-cef.sh`), 코드 서명, 스모크 검증
- `ThirdParty/CEF/` — 다운로드된 CEF 배포(.gitignore, 커밋 안 함)
- `App/` — 메인 앱(SwiftUI 진입점, 메뉴)
- `Bridge/` — Objective-C++(.mm) CEF↔Swift 어댑터
- `Helper/` — CEF 헬퍼 서브프로세스 실행자
- `Packages/GoatBrowserKit/` — SwiftPM(BrowserEngine / CEFEngine / BrowserCore / BrowserUI)

엔진: CEF (Chromium Embedded Framework), 고정 버전은 `scripts/cef-version.txt` 참조.

## MILESTONE 1 — 멀티탭 엔진 + 사이드바 + 커맨드바 + 내비게이션

- **탭당 CEF 브라우저 1개.** 하나의 안정적인 컨테이너 `NSView`(`GoatBrowserContainerView`)에
  모든 브라우저를 자식으로 붙이고, 탭 전환은 가시성(`isHidden`)/프레임 토글로만 처리
  (SwiftUI diff에서 재부모화하지 않음). 백그라운드 탭의 브라우저는 살려 둠(메모리 절약은 이후 마일스톤).
- **엔진은 파사드 뒤에 숨김.** Swift/SwiftUI는 CEF/C++ 심볼을 직접 임포트하지 않고
  ObjC `GoatCEF` 파사드만 호출. 헤더는 순수 ObjC(CEF 타입 노출 없음).
- **콜백 마샬링.** CEF UI 스레드 콜백은 전부 `dispatch_async(main)`으로 메인 큐에 넘긴 뒤
  `GoatCEFDelegate`(ObjC 프로토콜)로 전달 → Swift `@Observable` 메인 액터 모델이 안전하게 갱신.
- **OnBeforePopup** 은 네이티브 팝업을 취소하고 Swift에 새 탭 요청을 보냄(window.open / target=_blank).
- **Swift 모델 위치:** 지금은 단순화를 위해 `App/`에 둠(`Tab`, `BrowserViewModel`,
  `URLInputResolver`). `Packages/GoatBrowserKit/`로의 모듈화는 이후 진행. (계획 문서의 "App/에 두기" 선택)
- **UI:** 좌측 사이드바(탭 목록 + favicon/글로브 + 활성 강조 + hover ✕ + "+ New Tab"),
  콘텐츠 영역(단일 컨테이너), Cmd+L 커맨드바 오버레이, 좌상단 hover 내비 컨트롤(뒤로/앞으로/새로고침).
- **단축키:** Cmd+T 새 탭, Cmd+W 탭 닫기, Cmd+L 커맨드바, Cmd+[ / Cmd+] 뒤/앞,
  Cmd+R 새로고침, Cmd+\ 사이드바 토글, Cmd+Opt+I 개발자 도구 (메뉴 `Commands{}`로 연결).
- **배포 타깃 13.0 → 14.0** 으로 상향(`@Observable`/`@Bindable` 요구).
- **검증:** `scripts/smoke.sh` 가 (1) example.com 렌더, (2) `scripts/multitab_cdp.py` 로
  window.open → OnBeforePopup → 두 번째 CDP page 타깃 생성(멀티탭)을 확인.
