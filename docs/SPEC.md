# 알림펫 명세서

> 사용법은 [README](../README.md)를 보세요. 이 문서는 무엇을 왜 어떻게 만들었는지 정리한 개발 명세서입니다.

노트북 화면 위에 펫을 띄워두고, 알림이 오면 펫이 **말풍선으로 직접 말하는 것처럼** 보여주는 macOS 데스크톱 앱.

```
                ┌──────────────────────────┐
                │ 집가고싶어ㅠㅠ              │
                │ 💬 카카오톡       - 손범수  │
                └────────────┬─────────────┘
                             ▼
                          (=^･ω･^=)      ← 각도·크기 자유 조절
```

> 핵심 기능: **① 회전 ② 자유 크기 조절 ③ 알림 말풍선 ④ 펫별 알람**

---

## 1. 목표

| # | 기능 | 한 줄 요약 |
|---|------|-----------|
| F1 | 펫 띄우기 | 투명 배경 펫이 모든 창 위에 떠 있음 (desktop-pet 기능 그대로) |
| F2 | **각도 조절** | 캐릭터를 0°~360° 원하는 각도로 회전 |
| F3 | **크기 조절** | 캐릭터 크기를 슬라이더뿐 아니라 마우스로 자유롭게 변경 |
| F4 | **알림 말풍선** | 알림이 오면 캐릭터 머리 위에 `앱: 내용 - 보낸사람` 말풍선 표시 |

---

## 2. desktop-pet에서 가져오는 것

참고 저장소의 구조와 코드를 최대한 재사용한다.

| 가져올 것 | 원본 위치 | 비고 |
|-----------|-----------|------|
| 투명·항상 위 오버레이 창 | `Window/OverlayWindow.swift` | borderless, `.floating`, 모든 Space + 전체화면 위 표시 |
| 펫 렌더링 / 드래그 이동 / 파일 드롭 | `Window/PetView.swift` | `CALayer.contents = CGImage` 방식 |
| 창 크기·위치 관리 | `Window/OverlayWindowController.swift` | 회전·크기 로직을 여기에 추가 |
| 애니메이션 재생 | `Playback/*` | GIF / APNG / PNG 시퀀스 / 영상, `CVDisplayLink` |
| 펫별 설정 + 저장 | `Settings/AppSettings.swift`, `PetsStore.swift` | `rotation` 등 새 필드 추가 |
| 설정 패널 | `Settings/SettingsView.swift` | 회전·크기·말풍선 옵션 UI 추가 |
| 메뉴바 아이콘 | `MenuBar/MenuBarController.swift` | 알림 관련 메뉴 추가 |

**기존에 이미 있는 펫 옵션** (그대로 유지): Name, Playing, Speed, Opacity, Scale(0.25×~4.0×), Always on Top, Click-Through, Lock Position, Start at Login.
(Flip H/V는 설정 화면에서 뺐다. 회전으로 대신한다.)
설정 저장 위치: `~/Library/Application Support/desktop-pet/pets.plist` → 알림펫에서는 `~/Library/Application Support/NotiPet/pets.plist`로 변경.

Windows 버전(`DesktopPet.Windows/`)은 사용하지 않는다. **macOS 전용.**

---

## 3. 기능 명세

### F2. 캐릭터 각도 조절 (신규)

#### 요구사항
- 캐릭터를 **-180° ~ +180°** 범위에서 1° 단위로 회전할 수 있다.
- 회전 중심은 캐릭터 이미지의 **중앙**.
- 회전해도 캐릭터가 창 밖으로 잘리지 않는다.
- 각도는 펫마다 따로 저장되고, 재실행 시 복원된다.

#### 조작 방법
| 방법 | 동작 |
|------|------|
| 설정 패널 슬라이더 | `Rotation` 슬라이더 (-180°~180°) + 숫자 직접 입력 칸 |
| 회전 핸들 드래그 | `⌥ Option` 누른 채 캐릭터에 마우스를 올리면 위쪽에 ⟳ 핸들 표시 → 드래그해서 회전 |
| 단축키 | 캐릭터 선택 상태에서 `⌥ + ←/→` : 5°씩, `⌥ + ⇧ + ←/→` : 1°씩 |
| 스냅 | 핸들 드래그 중 `⇧ Shift` 누르면 15° 단위로 스냅 |
| 초기화 | 캐릭터 우클릭 → `각도 초기화` (0°로) |

#### 구현 방식
- `PetView`의 `imageLayer.transform`에 회전을 추가한다. 기존 Flip 변환과 합성:
  ```swift
  var t = CATransform3DIdentity
  t = CATransform3DRotate(t, rotation * .pi / 180, 0, 0, 1)
  if flipHorizontal { t = CATransform3DScale(t, -1, 1, 1) }
  if flipVertical   { t = CATransform3DScale(t, 1, -1, 1) }
  imageLayer.transform = t
  ```
- 회전하면 이미지가 차지하는 영역이 커지므로, **창 크기 = 회전된 이미지의 바운딩 박스**로 다시 계산한다.
  ```
  W' = |w·cosθ| + |h·sinθ|
  H' = |w·sinθ| + |h·cosθ|
  ```
  창 크기가 바뀔 때 캐릭터 **중심 위치는 고정**되도록 origin을 보정한다.
- 바운딩 박스 중 이미지가 없는 투명 영역은 클릭이 아래 창으로 통과되도록, `hitTest`에서 **현재 프레임의 알파값**을 확인한다 (알파 < 0.1이면 통과).

---

### F3. 캐릭터 크기 자유 조절 (개선)

desktop-pet에는 이미 `Scale` 슬라이더(0.25×~4.0×)가 있다. 이를 **더 자유롭게** 바꾼다.

#### 요구사항
- 크기 범위를 **0.1× ~ 8.0×** 로 넓힌다.
- 슬라이더 말고도 **마우스로 직접** 크기를 바꿀 수 있다.
- 가로세로 비율은 항상 유지된다.
- 크기를 바꿀 때 캐릭터 **중심(또는 반대쪽 모서리)이 고정**되어 튀지 않는다.
- 크기는 펫마다 저장·복원된다.
- 화면보다 커지지 않도록 최대 크기를 현재 모니터 크기로 제한한다.

#### 조작 방법
| 방법 | 동작 |
|------|------|
| 설정 패널 슬라이더 | `Scale` 슬라이더 + 퍼센트(%) 직접 입력 칸 |
| 모서리 핸들 드래그 | `⌥ Option` 누른 채 마우스를 올리면 네 모서리에 □ 핸들 표시 → 드래그해서 크기 조절 (반대쪽 모서리 고정) |
| 스크롤 | 캐릭터 위에서 `⌘ Command + 스크롤` → 확대/축소 (중심 고정) |
| 트랙패드 핀치 | 캐릭터 위에서 핀치 → 확대/축소 (`magnify(with:)`) |
| 단축키 | `⌘ + =` / `⌘ + -` : 10%씩, `⌘ + 0` : 원래 크기(1.0×) |

#### 구현 방식
- `OverlayWindowController.applyScale(_:)`을 재사용하되, 회전과 함께 계산하도록 순서를 정리한다:
  `원본 크기 × scale → 회전 바운딩 박스 → 창 크기`
- 핸들 드래그·스크롤·핀치는 모두 `settings.scale` 값만 바꾸고, 실제 창 크기 변경은 `settings.$scale` 구독 한 곳에서 처리한다 (기존 구조 유지).
- 일반 상태에서는 핸들이 보이지 않아 캐릭터가 깔끔하게 보이고, `⌥`를 누를 때만 편집 모드가 된다. `Lock Position`이 켜져 있으면 편집 모드도 막는다.

---

### F4. 알림 말풍선 (신규)

#### 요구사항
- 알림이 오면 캐릭터 **머리 위에 말풍선**이 나타나 캐릭터가 말하는 것처럼 보인다.
- 말풍선 형식 (두 줄):
  ```
  {내용}
  [앱 아이콘] {앱 이름}        - {보낸 사람}
  ```
- 보낸 사람이 없는 알림은 아랫줄에 앱 이름만 표시한다.
- 말풍선은 일정 시간(기본 **5초**) 뒤 자동으로 사라진다. 말풍선을 클릭하면 바로 닫힌다.
- 알림이 여러 개 동시에 오면 **큐**에 쌓아 하나씩 순서대로 보여준다.
- 말하는 동안 캐릭터가 살짝 통통 튀는 애니메이션을 한다 (선택 옵션).

#### 말풍선 디자인
```
┌──────────────────────────────┐
│ 집가고싶어ㅠㅠ                  │   ← 내용: 크게 (14pt), 최대 3줄
│ 💬 카카오톡           - 손범수  │   ← 작은 회색 글씨 (11pt): 앱은 왼쪽, 보낸 사람은 오른쪽
└───────────────┬──────────────┘
                ▼                       ← 꼬리: 캐릭터 머리 쪽을 가리킴
             (캐릭터)
```
- 내용을 가장 크게 보여주고, 앱 이름·보낸 사람은 아랫줄에 작게 둔다.
- 앱 아이콘은 설치된 앱에서 찾아 표시한다 (못 찾으면 생략).
- Discord/Slack의 `**굵게**` 같은 마크다운은 실제 굵은 글씨로 표시한다.
- 최대 너비 280pt, 내용이 길면 최대 3줄까지 보이고 나머지는 `…`로 자른다. 보낸 사람 이름이 길면 한 줄에서 `…`로 자른다.
- 캐릭터가 **회전**되어 있어도 말풍선은 **항상 수평**으로 표시한다.
- 캐릭터가 화면 위쪽 끝에 있어 공간이 없으면 말풍선을 **캐릭터 아래**에 띄우고 꼬리 방향을 뒤집는다. 좌우도 화면 밖으로 나가지 않게 위치를 보정한다.
- 라이트/다크 모드 둘 다 지원한다.

#### 구현 방식
- 말풍선은 펫 창과 **별도의 투명 창**(`SpeechBubbleWindow`)으로 만든다.
  - 펫 창 안에 넣으면 회전에 같이 돌아가고, 창 크기 밖으로 잘리기 때문.
  - 펫 창이 이동/크기변경/회전될 때 말풍선 창 위치도 따라간다 (펫 창의 `didMove`, `didResize` 알림 구독).
- 말풍선 내용은 SwiftUI 뷰(`SpeechBubbleView`)로 그리고 `NSHostingView`로 창에 넣는다.
- 나타날 때 살짝 커지며 페이드인, 사라질 때 페이드아웃.

#### 알림 데이터 형태
모든 알림 소스는 아래 구조로 변환되어 `SpeechQueue`로 들어간다.
```swift
struct PetMessage {
    let app: String       // "카카오톡"
    let body: String      // "집가고싶어ㅠㅠ"
    let sender: String?   // "손범수" (없으면 nil)
    let date: Date
}

extension PetMessage {
    var bubbleText: String {
        if let sender, !sender.isEmpty {
            return "\(app): \(body) - \(sender)"
        }
        return "\(app): \(body)"
    }
}
```

#### 펫마다 따로 하는 설정 (펫 설정 → 알림 탭)

알림이 오면 **조건에 맞는 모든 펫이 각자 자기 말풍선으로** 말한다. 예) A펫은 카카오톡만, B펫은 Discord만.

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| 이 펫이 알림 말하기 | ON | 끄면 이 펫은 알림을 말하지 않음 |
| 말풍선 크기 | 100% | 70%~200%. 글자·여백·꼬리가 같은 비율로 커짐 |
| 표시 시간 | 5초 | 2~15초 |
| 말할 때 통통 튀기 | ON | |
| 알림 소리 / 볼륨 | 뿅 / 60% | 뿅·삐롱·뽀잉 / macOS 기본 소리 / 없음 |
| 소리 내서 읽기 (TTS) | OFF | `AVSpeechSynthesizer`로 한국어 음성 읽기 |
| 말해줄 앱 / 무시할 앱 | 전체 / 없음 | 쉼표로 구분. 원래 앱 이름·바꾼 이름 둘 다 인식 |

#### 앱 전체 설정 (🐾 → 알림 설정…)
| 옵션 | 기본값 | 설명 |
|------|--------|------|
| 알림 말풍선 켜기 (모든 펫) | ON | 전체 일시정지 스위치 |
| 앱 이름 바꾸기 | `KakaoTalk → 카카오톡` | 시스템 앱 이름을 보기 좋은 이름으로 |
| 시스템 알림 읽기 / 원래 배너 숨기기 / 로컬 HTTP | | 알림을 어디서 가져올지 |

---

### F5. 펫별 알람 (신규)

#### 요구사항
- 알람은 **펫마다 따로** 만들고 저장한다 (앱을 껐다 켜도 유지).
- 할 일 + 시간 + 반복 요일. 요일을 고르지 않으면 한 번만 울리고 자동으로 꺼진다.
- "5분 뒤 / 10분 뒤 / 30분 뒤 / 1시간 뒤" 빠른 추가.
- 목록에서 켜기/끄기, 삭제. 꺼진 한 번짜리 알람을 다시 켜면 다음 그 시각에 울린다.
- 목록의 알람을 누르면 입력 칸에 불러와 수정한다 ([저장] / [취소]). 저장하면 같은 id로 바뀌고 다시 켜진다.

#### 울리는 방식 (진짜 알람처럼)
```
┌───────────────────────────┐
│ ⏰ 07:30                   │
│ 일어나기                    │   ← 크게
│ [5분 뒤 다시]  [끄기]        │
└────────────┬──────────────┘
             ▼
          (펫이 덜덜 흔들림)
```
- 알람 소리가 **끄기 전까지 반복**되고, 작게 시작해서 20초에 걸쳐 설정한 볼륨까지 커진다.
- 펫이 좌우로 흔들리며 들썩이고, 말풍선은 주황색으로 빛나며 살짝 맥박친다.
- 숨겨 둔 펫이면 다시 나타나서 울린다. "알림 말풍선 끄기"와 상관없이 울린다.
- 10분 동안 안 끄면 소리·흔들림만 멈추고 말풍선은 "놓친 알람"으로 남는다.
- [5분 뒤 다시]는 알람의 `snoozeUntil`로 저장한다 (앱을 껐다 켜도 유지). 스케줄러가 그 시각에 한 번 더 울리고 지운다. 알람을 끄면 같이 취소된다. 테스트 알람처럼 목록에 없는 알람은 메모리에만 둔다.
- 같은 펫에 알람이 겹치면 차례로 울린다. 알람이 떠 있는 동안 그 펫의 일반 알림 말풍선은 기다렸다가 이어서 나온다.
- Mac이 잠자기 중이었으면, 깨어났을 때 30분 이내에 놓친 알람은 울리고 그보다 오래된 건 건너뛴다.
- 알람 소리: 따르릉 / 삐삐삐삐 / 딩동댕 / 뽀잉뽀잉 / macOS 기본 소리 (펫마다 선택, 미리 듣기, 볼륨).

---

## 4. 알림을 어떻게 받아올 것인가

macOS는 **다른 앱의 알림을 읽는 공식 API를 제공하지 않는다.** 그래서 단계별로 접근한다.

| 방식 | 설명 | 난이도 | 비고 |
|---|---|---|---|
| A. 로컬 HTTP / CLI | `curl localhost:7777/say ...`로 외부에서 펫에게 말 시키기 | 쉬움 | 말풍선 UI 개발·테스트용. 스크립트, 빌드 완료 알림 등과 연동 |
| B. 자체 알림 | 펫별 알람 (F5) | 쉬움 | 권한 불필요 |
| C. 손쉬운 사용(Accessibility) API | 화면에 뜨는 알림 배너 UI를 감지해 앱 이름·보낸 사람·내용 추출 | 중간 | **카카오톡 같은 실제 앱 알림은 이 방식.** "손쉬운 사용" 권한 필요, macOS 버전마다 배너 구조가 다를 수 있음 |
| D. 알림 센터 DB 읽기 | `usernoted` 데이터베이스 직접 조회 | 어려움 | 전체 디스크 접근 권한 필요, 최신 macOS에서 막힐 수 있어 비추천 |

→ **A로 말풍선을 먼저 완성하고, C로 카카오톡 등 실제 알림을 연결**한다.

카카오톡 알림 배너 → `PetMessage` 변환 예:
| 배너 요소 | 값 | → 필드 |
|-----------|----|--------|
| 앱 | KakaoTalk | `app = "카카오톡"` (이름 바꾸기 적용) |
| 제목 | 손범수 | `sender = "손범수"` |
| 본문 | 집가고싶어ㅠㅠ | `body = "집가고싶어ㅠㅠ"` |

---

## 5. 기술 스택

- **Swift + AppKit** (desktop-pet과 동일) + 말풍선·설정 UI는 **SwiftUI**
- **렌더링**: `CALayer` + `CVDisplayLink` (desktop-pet 재사용)
- **회전/크기**: `CATransform3D`, 창 프레임 재계산
- **알림 감지**: Accessibility API (`AXUIElement`, `AXObserver`)
- **로컬 서버**: `Network.framework`의 `NWListener`
- **TTS**: `AVSpeechSynthesizer`
- **최소 지원**: macOS 14+

---

## 6. 프로젝트 구조

```
알림펫/
├── README.md
├── NotiPet/
│   ├── App/                        # AppDelegate, main.swift, Info.plist          (desktop-pet)
│   ├── Playback/                   # 애니메이션 디코더·재생                        (desktop-pet)
│   ├── Utilities/                  # 북마크 (desktop-pet), 앱 이름 목록(AppDirectory),
│   │                               # 알람시계 고양이 그림(AlarmCatArt) + 기본 펫 애니메이션        (수정)
│   ├── Resources/AppIcon.iconset                                                    (desktop-pet)
│   ├── MenuBar/
│   │   └── MenuBarController.swift # + 알림 on/off, 최근 알림 메뉴                 (수정)
│   ├── Settings/
│   │   ├── AppSettings.swift       # + rotation, 크기 범위 확장                    (수정)
│   │   ├── PetsStore.swift         # + rotation 저장                               (수정)
│   │   ├── SettingsView.swift      # + 각도/크기 슬라이더·숫자 입력                 (수정)
│   │   ├── NotificationSettings.swift      # 앱 필터, 이름 바꾸기, 표시 시간    (신규)
│   │   ├── PetReminder.swift       # 알람 (시간·요일·한 번)                    (신규)
│   │   └── NotificationSettingsView.swift  # 알림 설정 패널                     (신규)
│   ├── Window/
│   │   ├── OverlayWindow.swift                                                     (desktop-pet)
│   │   ├── OverlayWindowController.swift  # + 회전 바운딩 박스, 크기 계산, 클릭 통과 (수정)
│   │   └── PetView.swift           # + 회전 transform, ⌥ 핸들, 스크롤/핀치, 알파 hitTest (수정)
│   ├── Speech/
│   │   ├── PetMessage.swift        # 알림 공통 데이터                              (신규)
│   │   ├── SpeechQueue.swift       # 큐, 표시 시간, TTS                            (신규)
│   │   ├── SpeechBubbleWindow.swift   # 펫을 따라다니는 말풍선 창                   (신규)
│   │   ├── SpeechBubbleView.swift     # 말풍선 SwiftUI 뷰                          (신규)
│   │   ├── PetSound.swift / AlarmSound.swift  # 알림 효과음 / 반복 알람 소리       (신규)
│   │   ├── AlarmCenter.swift          # 알람 울리기·끄기·5분 뒤 다시               (신규)
│   │   └── AlarmBubbleView.swift      # 알람 말풍선                                (신규)
│   └── Sources/                    # 알림 소스                                     (신규)
│       ├── NotificationSource.swift      # 공통 프로토콜
│       ├── LocalServerSource.swift       # A. HTTP로 말 시키기
│       ├── ReminderScheduler.swift       # B. 펫별 알람 시간 체크 → AlarmCenter
│       └── AccessibilitySource.swift     # C. 시스템 알림 배너 감지
├── Tests/                          # 자동 테스트 (XCTest 없이 실행)
├── build.sh                        # swiftc로 build/NotiPet.app 빌드 (Xcode 불필요)
├── test.sh                         # Tests/ 실행
├── scripts/make-icon.swift         # AlarmCatArt로 앱 아이콘 AppIcon.iconset 생성
├── scripts/setup-signing.sh        # 로컬 서명 인증서 "NotiPet Dev" 만들기
└── LICENSE                         # MIT (desktop-pet 저작권 표기 포함)
```

---

## 7. 개발 로드맵

- [x] **1단계 – 기반 가져오기**: desktop-pet 코드 가져와서 빌드, 이름을 AlarmPet으로 변경 (나중에 NotiPet으로 다시 바꿈), 펫 띄우기 확인
- [x] **2단계 – 크기 자유 조절**: 범위 0.1×~8.0×, 숫자 입력, `⌘+스크롤`, 핀치, 모서리 핸들
- [x] **3단계 – 각도 조절**: 회전 transform, 바운딩 박스 창 크기, 슬라이더·핸들·단축키, 알파 기반 클릭 통과
- [x] **4단계 – 말풍선**: `SpeechBubbleWindow`, `앱: 내용 - 보낸사람` 형식, 큐, 자동 사라짐, 화면 끝 위치 보정
- [x] **5단계 – 로컬 HTTP**: `curl`로 펫에게 말 시키기 (말풍선 테스트용)
- [x] **6단계 – 실제 알림 연결**: Accessibility 권한 요청, 카카오톡 등 알림 배너 감지, 앱 필터·이름 바꾸기, 원래 배너 닫기 (카카오톡·디스코드 실기기 확인)
  - macOS 26.6에서 검증. 배너 구조는 버전마다 달라질 수 있으니 안 되면 `open --env NOTIPET_AX_DEBUG=1 build/NotiPet.app` 로 실행하고 `~/Library/Logs/NotiPet/ax.log` 확인
- [x] **7단계 – 다듬기**: TTS, 말할 때 통통 튀는 애니메이션 (집중 모드 감지는 macOS가 파일 접근을 막아 제거)
- [x] **8단계 – 펫별 설정·알람**: 펫마다 알림 설정, 펫별 알람(수정, "5분 뒤 다시" 저장), 알람시계 고양이 아이콘·기본 펫, 로컬 HTTP 포트 설정, 자동 테스트(`./test.sh`)

---

## 8. 사용 예시

```bash
# 펫에게 말 시키기 (말풍선 테스트)
curl -X POST localhost:7777/say \
  -H 'Content-Type: application/json' \
  -d '{"app": "카카오톡", "body": "집가고싶어ㅠㅠ", "sender": "손범수"}'
# → 말풍선: 집가고싶어ㅠㅠ / 카카오톡 - 손범수

# 특정 펫에게만 말 시키기 ("pet": 펫 이름 또는 id)
curl -X POST localhost:7777/say -d '{"app": "터미널", "body": "빌드 끝!", "pet": "kurukuru"}'

# 긴 작업이 끝나면 알려주기
npm run build && curl -X POST localhost:7777/say -d '{"app": "터미널", "body": "빌드 성공 🎉"}'
# → 말풍선: 빌드 성공 🎉 / 터미널
```

---

## 9. 필요한 권한

- **손쉬운 사용** (시스템 알림 읽기를 켤 때만): 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → NotiPet 허용
  - `build.sh`는 로그인 키체인의 **"NotiPet Dev"** 자체 서명 인증서가 있으면 그걸로 서명해서, 다시 빌드해도 권한이 유지돼요. 인증서가 없으면 ad-hoc 서명이라 빌드할 때마다 권한을 다시 줘야 해요.
  - 권한 목록에 켜져 있는데도 안 되면: `tccutil reset Accessibility com.sonbumsu.notipet` 후 앱을 다시 실행해서 허용.
- 그 외 기능은 별도 권한 없음

## 9-1. 알려진 제한

- 펫을 화면 위쪽 끝 너머로 두면 macOS가 창을 메뉴바 아래로 밀어 넣어요.
- 집중 모드 감지 기능은 뺐다. 공식 API가 없고, 상태 파일(`~/Library/DoNotDisturb/DB/Assertions.json`)은 macOS가 읽기를 막는다(전체 디스크 접근 권한 필요). 집중 모드 중에는 macOS 배너 자체가 안 떠서 펫도 말하지 않는다.
- 영상(MP4/MOV) 펫은 투명 영역 판정을 하지 않아 사각형 전체가 클릭을 받아요.

---

## 10. 참고 / 주의

- 알림 내용은 기기 밖으로 전송하지 않고 **로컬에서만** 처리한다. 로컬 서버는 `127.0.0.1`에만 바인딩한다.
- desktop-pet은 MIT 라이선스이므로 코드를 가져올 때 원본 저작권 표기(`Copyright (c) 2025 bssm-oss`)를 `LICENSE`에 유지한다.
- 펫 이미지 저작권에 주의 (직접 그리거나 사용 허가된 리소스 사용).
- 참고: [bssm-oss/desktop-pet](https://github.com/bssm-oss/desktop-pet) — [Architecture](https://github.com/bssm-oss/desktop-pet/blob/main/docs/architecture.md), [Formats](https://github.com/bssm-oss/desktop-pet/blob/main/docs/formats.md)
