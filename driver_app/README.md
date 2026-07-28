# T-Ride Driver Android

독립적인 Flutter Android 기사 앱입니다. 기존 고객·기사·관리자 웹과 backend를 변경하지 않습니다.

## 환경

| Flavor | Entrypoint | Application ID | 앱 이름 | API |
| --- | --- | --- | --- | --- |
| `dev` | `lib/main_dev.dart` | `com.trider.driver.dev` | `TRide Driver DEV` | Android emulator 개발 주소 |
| `stg` | `lib/main_stg.dart` | `com.trider.driver.staging` | `TRide Driver STG` | `https://trider.taxi` staging API |
| `prod` | `lib/main_prod.dart` | `com.trider.driver` | `TRide Driver` | 비활성(주소 확정 전 요청 차단) |

기본 `lib/main.dart`는 안전하게 DEV 환경을 사용합니다. flavor와 entrypoint를 항상 함께 지정합니다.

DEV만 emulator 로컬 서버를 위해 cleartext HTTP를 허용합니다. STG와 PROD는 HTTPS만 허용하며 Android cleartext도 비활성화합니다.

### 빌드

flavor가 설정되어 있으므로 **flavor와 entrypoint 없이** `flutter build apk --debug`만 실행하면 Gradle은 성공해도 APK(`app-debug.apk`)가 생성되지 않습니다. 아래처럼 flavor를 반드시 지정하세요.

```powershell
flutter build apk --debug --flavor dev -t lib/main_dev.dart
flutter build apk --debug --flavor stg -t lib/main_stg.dart
```

STG debug APK 산출물:

```text
build/app/outputs/flutter-apk/app-stg-debug.apk
```

Production release APK는 별도 signing 설정이 완료된 뒤에만 빌드합니다. signing이 준비되지 않았다면 release 빌드가 성공한다고 가정하지 마세요.

```powershell
flutter build apk --release --flavor prod -t lib/main_prod.dart
```

### 실행

```powershell
flutter run --flavor stg -t lib/main_stg.dart
```

실기기 설치 예 (STG):

```powershell
adb install -r build/app/outputs/flutter-apk/app-stg-debug.apk
```

Production release signing은 별도의 승인된 보안 절차로 구성해야 합니다. 이 PR은 production release build를 지원하지 않으며 debug key로 production release를 만들지 않습니다.

## 검증

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter pub get
flutter test
flutter analyze
```

실제 계정이나 token을 소스, 테스트, 로그 또는 artifact에 포함하지 않습니다.
