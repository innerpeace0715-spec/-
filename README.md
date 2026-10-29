# U-file

**U-file**은 [FileMoa](https://github.com/cybereun/FileMoa)(Windows 파일 정리 앱)를 **갤럭시 탭 S9+**와
**iPad**에서 쓰도록 바꾼 앱입니다. 영상은 앱 안에서 [FilmCraft](https://github.com/storytold/filmcraft) 편집기로 바로 수정할 수 있습니다. `분석 → 미리보기 → 승인 → 이동 → 기록 → 되돌리기` 흐름과 안전장치는
그대로이고, 태블릿 화면과 안드로이드 저장소에 맞게 고쳤습니다. 원본 Windows 설명은
[`README.windows.md`](README.windows.md)에 있습니다.

## 설치 (갤럭시 탭)

1. GitHub의 **Actions → U-file (Galaxy Tab + iPad)**에서 최근 성공한 실행을 열고, 아래쪽
   **Artifacts**의 `U-file-GalaxyTab-verified`를 내려받아 압축을 풉니다. 이 묶음은 안드로이드
   태블릿 에뮬레이터에 설치해 정리·되돌리기·중복 삭제·영상 편집·내보내기까지 자동으로 확인을
   통과한 APK와 그 검사 결과(`selftest.json`)입니다.
2. `U-file-GalaxyTab-<버전>.apk`를 탭으로 옮겨(구글 드라이브·USB·Quick Share) 엽니다.
   "출처를 알 수 없는 앱" 설치를 허용해야 합니다.
3. 처음 실행하면 **모든 파일에 대한 접근** 설정 화면이 열립니다. U-file을 허용하고 돌아오세요.
   나중에 허용하려면 앱 위쪽의 노란 안내에서 `권한 설정 열기`를 누르면 됩니다.

### 업데이트를 덮어쓰기로 설치하려면 (선택)

안드로이드는 **같은 키로 서명된 APK만** 기존 앱 위에 설치합니다. 서명 키를 저장소 비밀로
넣어 두지 않으면 빌드마다 새 키를 쓰기 때문에, 새 버전을 설치하기 전에 기존 앱을 지워야 하고
정리 기록도 함께 사라집니다. 한 번만 설정하면 됩니다.

```bash
keytool -genkeypair -keystore filemoa.jks -alias filemoa -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 filemoa.jks   # 출력된 긴 글자를 복사
```

저장소 **Settings → Secrets and variables → Actions**에 다음 두 값을 추가합니다.

- `ANDROID_KEYSTORE_BASE64`: 위에서 복사한 글자
- `ANDROID_KEYSTORE_PASSWORD`: keytool에서 정한 비밀번호

`filemoa.jks` 파일은 잃어버리지 않게 따로 보관하세요. 저장소에는 올리지 마세요.

## 설치 (iPad)

App Store를 거치지 않는 앱이라, 내 Apple ID로 직접 서명해서 설치해야 합니다(무료 Apple ID로 가능).

1. 같은 Actions 실행의 **Artifacts**에서 `U-file-iPad`를 내려받아 압축을 풉니다. 안에 있는
   `U-file-iPad-<버전>-unsigned.ipa`가 앱이고, `selftest.json`은 같은 코드로 만든 앱을 iPad 시뮬레이터에서
   자동 검사한 결과입니다.
2. PC나 Mac에 [Sideloadly](https://sideloadly.io/)(또는 AltStore)를 설치하고, iPad를 케이블로 연결한 뒤
   IPA를 끌어다 놓고 Apple ID로 로그인해 설치합니다.
3. iPad의 **설정 → 일반 → VPN 및 기기 관리**에서 내 Apple ID 개발자를 신뢰합니다. iPadOS 16 이상이라면
   **설정 → 개인정보 보호 및 보안 → 개발자 모드**도 켜야 합니다.
4. 무료 Apple ID로 서명한 앱은 **7일마다 다시 서명**해야 합니다(Sideloadly에서 다시 설치하면 정리 기록은
   그대로 남습니다). 유료 Apple 개발자 계정(연 $99)이라면 1년간 유지됩니다.

iPad에서 정리할 파일은 **파일 앱 → 나의 iPad → U-file** 폴더에 넣습니다. iPadOS는 앱이 자기 폴더 밖의
파일(다른 앱, iCloud Drive)을 마음대로 옮기지 못하게 막기 때문입니다. 정리 결과, 휴지통
(`U-file_휴지통`), 영상 편집 결과(`U-file`)도 모두 이 폴더 안에 생깁니다.

## 외부 전송 없음

탭용·iPad용 U-file은 **파일도, 파일 이름도 기기 밖으로 보내지 않습니다.**

- APK에 인터넷 권한(`INTERNET`)이 아예 없습니다. 그래서 앱이 바깥에 연결하려 해도 안드로이드가 막습니다.
  CI는 설치한 APK에 이 권한이 없는지, 바깥 주소로의 요청이 실제로 막히는지 매번 확인합니다.
- 화면(WebView)도 앱 안의 페이지·기기의 파일에만 접근하도록 제한했습니다(CSP).
- iPad판에는 인터넷 권한이라는 개념이 없지만, 연결을 여는 코드 자체가 빠져 있고 화면도 바깥 주소에
  연결하지 못하게 막혀 있습니다(시뮬레이터 검사에서 같은 방식으로 확인).
- 그래서 탭과 iPad에서는 AI 분류(OpenAI·Claude·Gemini)가 빠져 있습니다. 정리, 되돌리기, 중복·대용량 파일,
  영상 편집은 모두 기기 안에서만 동작합니다.

## 탭에서 달라진 점

| 기능 | Windows 원본 | 갤럭시 탭 |
|---|---|---|
| 폴더 선택 | 탐색기 대화상자 | 앱 안의 폴더 목록(내장 저장소부터 탐색) + 빠른 폴더(다운로드·카메라·스크린샷·사진·문서·동영상·음악) |
| 휴지통 | Windows 휴지통 | 내장 저장소의 `U-file_휴지통/<날짜_시간>/` 폴더로 이동. 내 파일 앱에서 되살리거나 완전히 지울 수 있습니다 |
| 보호 경로 | Windows·Program Files·AppData 등 | `Android/`(앱 데이터)와 `U-file_휴지통`은 검사와 정리에서 제외. 내장 저장소·SD 카드 **전체**는 정리 대상으로 고를 수 없습니다 |
| AI 분류 | OpenAI·Claude·Gemini·Ollama | 없음(외부 전송을 하지 않기 위해 제외) |
| 자동 업데이트, 우클릭 메뉴, 한 창만 실행 | 있음 | 없음(APK로 설치) |

글꼴은 세리프체(Noto Serif KR, 앱에 포함)를 씁니다. 화면은 손가락으로 누르기 쉽게 버튼과 체크박스를 키웠고(48dp 기준), 글자도 키웠습니다.

- **가로 화면**: 작업 버튼과 정리 옵션이 한 줄에 놓여 미리보기 목록이 더 위에서 시작합니다.
- **세로 화면**: 긴 파일 이름이 잘리지 않고 두 줄로 보입니다.
- 미리보기 경로는 `내장 저장소/Download/...` 대신 고른 폴더 기준(`사진/이미지/IMG_0001.jpg`)으로 보여 줍니다.
- 긴 목록을 내려도 `파일 이동` 버튼이 화면 아래에 계속 떠 있습니다.
- 중복 파일 화면의 `남길 기준` 막대도 화면 위에 고정됩니다.

## 영상 수정 (FilmCraft)

`파일 수정` 버튼(정리 탭)으로 영상을 고르거나, 미리보기·대용량 파일 목록에서 영상 옆의 `수정`을
누르면 FilmCraft 편집 화면이 열립니다. 고른 영상은 새 시퀀스로 타임라인에 올라가 있습니다.

- FilmCraft 원본 코드는 `vendor/filmcraft`에 있습니다(storytold/filmcraft
  `8d925e9`, MIT/Apache-2.0). 그중 WebAssembly 웹 빌드를 앱 안에 넣어 **탭에서 직접** 실행합니다.
  인터넷 연결이나 서버가 필요 없습니다.
- 편집기에서 내보내기(Export)나 저장을 하면 결과 파일이 자동으로 기기에 저장됩니다.
  영상은 `내장 저장소/Movies/U-file/`, 그 밖의 파일(프로젝트 등)은 `내장 저장소/Download/U-file/`에
  저장되고, 같은 이름이 있으면 `(1)`을 붙입니다. 원본 영상은 건드리지 않습니다.
- 위쪽 `← U-file` 버튼으로 정리 화면으로 돌아갑니다. 내보내지 않은 편집 내용은 이때 사라집니다.
- 한계: FilmCraft 웹 빌드는 단일 스레드로 돌아가 데스크톱판보다 느립니다. 일부 기능(렌더 미리보기,
  프록시, 마스크 추적)은 웹에서 지원되지 않습니다. 편집기 화면은 영어이고, 웹 빌드에는 한글 글꼴이
  없어서 편집기 안의 한글 파일 이름은 네모로 보일 수 있습니다. 내보내기는 결과를 메모리에 만든 뒤
  저장하므로, 아주 긴 영상은 탭의 메모리를 많이 씁니다.

## 개발

```bash
npm ci
npm test -- --run
npm run build
cargo test --manifest-path src-tauri/Cargo.toml --lib
```

편집기를 포함하려면 먼저 FilmCraft 웹 빌드를 만듭니다(Rust 1.97, `wasm32-unknown-unknown`,
`wasm-bindgen-cli 0.2.129` 필요). 결과는 `public/filmcraft/`에 들어가 앱과 함께 묶입니다.

```bash
scripts/build-filmcraft.sh
```

APK를 직접 빌드하려면 Android SDK, NDK, JDK 17이 필요합니다. 환경 변수
`ANDROID_HOME`과 `NDK_HOME`을 설정한 뒤 다음을 실행하세요. 탭을 USB로 연결했다면
`npx tauri android dev`로 바로 실행해 볼 수도 있습니다.

```bash
npx tauri android build --apk --target aarch64
```

안드로이드 프로젝트는 `src-tauri/gen/android`에 있습니다. 권한 요청과 화면 여백 처리는
`MainActivity.kt`, 저장소 권한은 `AndroidManifest.xml`에서 다룹니다.

원본 저장소에는 라이선스가 명시되어 있지 않습니다. 이 저장소는 개인 사용 목적으로만 쓰고,
공개 배포하려면 원작자의 허락을 먼저 받으세요.
