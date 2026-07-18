# T-Ride Driver Android

독립적인 Flutter Android 기사 앱입니다. 기존 고객·기사·관리자 웹과 backend를 변경하지 않습니다.

## 환경

| Flavor | Entrypoint | Application ID | 앱 이름 | API |
| --- | --- | --- | --- | --- |
| `dev` | `lib/main_dev.dart` | `com.tride.driver.dev` | `TRide Driver DEV` | Android emulator 개발 주소 |
| `stg` | `lib/main_stg.dart` | `com.tride.driver.staging` | `TRide Driver STG` | 현재 저장소에 문서화된 staging API |
| `prod` | `lib/main_prod.dart` | `com.tride.driver` | `TRide Driver` | 비활성(주소 확정 전 요청 차단) |

기본 `lib/main.dart`는 안전하게 DEV 환경을 사용합니다. flavor와 entrypoint를 항상 함께 지정합니다.

```powershell
flutter run --flavor stg -t lib/main_stg.dart
flutter build apk --debug --flavor stg -t lib/main_stg.dart
```

## 검증

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter pub get
flutter test
flutter analyze
```

실제 계정이나 token을 소스, 테스트, 로그 또는 artifact에 포함하지 않습니다.
