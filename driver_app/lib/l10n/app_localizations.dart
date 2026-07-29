import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('th'),
    Locale('ko'),
  ];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  bool get _isKo => locale.languageCode == 'ko';

  String _s(String ko, String th) => _isKo ? ko : th;

  // Navigation
  String get tabNewCalls => _s('새 콜', 'งานใหม่');
  String get tabMyTrips => _s('내 운행', 'งานของฉัน');
  String get tabSettlement => _s('정산', 'การชำระเงิน');
  String get tabAccount => _s('계정', 'บัญชี');

  // Common actions
  String get cancel => _s('취소', 'ยกเลิก');
  String get retry => _s('다시 시도', 'ลองอีกครั้ง');
  String get save => _s('저장', 'บันทึก');
  String get upload => _s('업로드', 'อัปโหลด');
  String get submit => _s('제출', 'ส่ง');
  String get accept => _s('수락', 'รับงาน');
  String get logout => _s('로그아웃', 'ออกจากระบบ');
  String get refresh => _s('새로고침', 'รีเฟรช');
  String get select => _s('선택', 'เลือก');
  String get leave => _s('나가기', 'ออก');
  String get login => _s('로그인', 'เข้าสู่ระบบ');

  // Language selector
  String get languageKorean => _s('한국어', '한국어');
  String get languageThai => _s('ไทย', 'ไทย');
  String get selectLanguage => _s('언어 선택', 'เลือกภาษา');

  // Auth
  String get driverLogin => _s('기사 로그인', 'เข้าสู่ระบบคนขับ');
  String get driverAccountLabel =>
      _s('기사 계정 (전화번호 또는 이메일)', 'บัญชีคนขับ (เบอร์โทรหรืออีเมล)');
  String get driverAccountRequired =>
      _s('기사 계정을 입력해 주세요.', 'กรุณากรอกบัญชีคนขับ');
  String get password => _s('비밀번호', 'รหัสผ่าน');
  String get passwordRequired =>
      _s('비밀번호를 입력해 주세요.', 'กรุณากรอกรหัสผ่าน');
  String get showPassword => _s('비밀번호 표시', 'แสดงรหัสผ่าน');
  String get hidePassword => _s('비밀번호 숨기기', 'ซ่อนรหัสผ่าน');
  String get connectionFailed => _s('연결에 실패했습니다.', 'เชื่อมต่อไม่สำเร็จ');
  String get logoutFromThisDevice =>
      _s('이 기기에서 로그아웃', 'ออกจากระบบบนเครื่องนี้');
  String get loginSuccess => _s('로그인 성공', 'เข้าสู่ระบบสำเร็จ');
  String get tRideDriverTitle => _s('T-Ride 기사', 'T-Ride คนขับ');
  String environmentLabel(String env) =>
      _s('환경: $env', 'สภาพแวดล้อม: $env');
  String driverFallbackName(int id) =>
      _s('기사 #$id', 'คนขับ #$id');

  // Online status
  String get online => _s('온라인', 'ออนไลน์');
  String get offline => _s('오프라인', 'ออฟไลน์');
  String get canReceiveNewCalls =>
      _s('새 콜을 받을 수 있습니다.', 'พร้อมรับงานใหม่');
  String get newCallReceivingStopped =>
      _s('새 콜 수신이 중지되어 있습니다.', 'ปิดรับงานใหม่แล้ว');
  String get newCallReceivingStatus =>
      _s('새 콜 수신 상태', 'สถานะรับงานใหม่');
  String get goOnlineToSeeNewCalls =>
      _s('온라인으로 전환하면 새 콜을 볼 수 있습니다', 'เปิดออนไลน์เพื่อดูงานใหม่');

  // New calls / dispatch
  String get newCallsTitle => _s('새 콜', 'งานใหม่');
  String get acceptNewCallTitle => _s('새 콜 받기', 'รับงานใหม่');
  String acceptNewCallWithVehicle(String vehicleName) => _s(
        '$vehicleName 차량으로 이 콜을 받으시겠습니까?',
        'รับงานนี้ด้วยรถ $vehicleName ใช่ไหม?',
      );
  String get acceptCall => _s('콜 받기', 'รับงาน');
  String get callAssignmentCompleted =>
      _s('콜 배정이 완료되었습니다.', 'รับงานสำเร็จแล้ว');
  String get noNewCallsAvailable =>
      _s('현재 받을 수 있는 새 콜이 없습니다.', 'ตอนนี้ยังไม่มีงานใหม่');
  String get newCallsArrivedListRefreshed =>
      _s('새 콜이 도착해 목록을 갱신했습니다.', 'มีงานใหม่เข้ามา อัปเดตรายการแล้ว');
  String get unresolvedSettlementBlocksNewCalls => _s(
        '미해결 정산이 있어 새 콜을 받을 수 없습니다.',
        'มีการชำระเงินที่ยังไม่เสร็จ จึงรับงานใหม่ไม่ได้',
      );
  String get unresolvedSettlementCheckRequired =>
      _s('미해결 정산 확인 필요', 'ต้องตรวจสอบการชำระเงินที่ค้างอยู่');
  String get checkSettlement => _s('정산 확인하기', 'ตรวจสอบการชำระเงิน');
  String get urgentCallLabel => _s('긴급콜', 'งานด่วน');
  String get urgentChip => _s('긴급', 'ด่วน');
  String get noApprovedVehicleForCall => _s(
        '이 콜에 사용할 수 있는 승인 차량이 없습니다.',
        'ไม่มีรถที่อนุมัติแล้วสำหรับงานนี้',
      );
  String get customerRejectedOrRoundEnded => _s(
        '고객이 거절했거나 라운드가 종료되었습니다.',
        'ลูกค้าปฏิเสธหรือรอบการเจรจาจบแล้ว',
      );
  String get negotiationCancelled =>
      _s('협상이 취소되었습니다.', 'การเจรจาถูกยกเลิกแล้ว');
  String get etaInputExpired =>
      _s('ETA 입력 시간이 만료되었습니다.', 'หมดเวลากรอก ETA แล้ว');
  String get requestPassedToOtherDriver =>
      _s('다른 기사에게 넘어간 요청입니다.', 'คำขอนี้ไปอยู่กับคนขับคนอื่นแล้ว');
  String get otherDriverAlreadyAcceptedCall =>
      _s('다른 기사가 이미 수락한 콜입니다.', 'มีคนขับรับงานนี้ไปแล้ว');
  String get urgentCallNoLongerAcceptable =>
      _s('더 이상 수락할 수 없는 긴급콜입니다.', 'งานด่วนนี้รับไม่ได้แล้ว');
  String get otherDriverClaimedCallFirst => _s(
        '다른 기사가 먼저 이 콜을 배정받았습니다.',
        'มีคนขับรับงานนี้ไปก่อนแล้ว',
      );
  String meetingGateNumber(int gate) =>
      _s('$gate번 게이트', 'ประตู $gate');
  String passengersCount(int count) => _s('$count명', '$count คน');
  String previousRejectionRequiresEtaUnder(int minimumMinutes) => _s(
        '이전 거절로 $minimumMinutes분 미만 ETA 필요',
        'ถูกปฏิเสธก่อนหน้า ต้องใส่ ETA น้อยกว่า $minimumMinutes นาที',
      );
  String vehicleExactMatch(String vehicleMatchType) =>
      _s('$vehicleMatchType · 정확 일치', '$vehicleMatchType · ตรงตามที่จอง');
  String vehicleCompatibleUpgrade(String vehicleMatchType) => _s(
        '$vehicleMatchType · 호환 업그레이드',
        '$vehicleMatchType · อัปเกรดที่ใช้ได้',
      );
  String vehicleTypeAndPassengers(String vehicleTypeName, int count) => _s(
        '$vehicleTypeName · $count명',
        '$vehicleTypeName · $count คน',
      );
  String golfBagCount(int count) => _s('골프백 $count', 'กระเป๋ากอล์ฟ $count');

  // Vehicle select sheet
  String get selectTripVehicleTitle =>
      _s('운행 차량 선택', 'เลือกรถสำหรับงานนี้');
  String get selectVehicleForCallHint =>
      _s('이 콜에 사용할 차량을 선택해 주세요.', 'เลือกรถที่จะใช้รับงานนี้');
  String get exactVehicleMatch =>
      _s('예약 차량과 정확히 일치', 'ตรงกับรถที่ลูกค้าจอง');
  String get compatibleUpgradeVehicle =>
      _s('호환 가능한 상위 차량', 'รถระดับสูงกว่าที่ใช้ได้');

  // Urgent ETA dialog
  String get etaInputTitle =>
      _s('도착 예상 시간 입력', 'กรอกเวลาถึงโดยประมาณ');
  String remainingTime(String countdown) =>
      _s('남은 시간 $countdown', 'เวลาเหลือ $countdown');
  String previousRejectionEtaRequiredFull(int minimumMinutes) => _s(
        '이전 거절로 $minimumMinutes분 미만 ETA가 필요합니다.',
        'ถูกปฏิเสธก่อนหน้า ต้องใส่ ETA น้อยกว่า $minimumMinutes นาที',
      );
  String get etaMinutesLabel => _s('ETA (분)', 'ETA (นาที)');
  String get etaMinimumIntegerError =>
      _s('1분 이상의 정수를 입력해 주세요.', 'กรุณากรอกตัวเลขเต็มอย่างน้อย 1 นาที');
  String etaMustBeUnderMinutes(int minimumMinutes) => _s(
        '$minimumMinutes분 미만으로 입력해 주세요.',
        'กรุณากรอกน้อยกว่า $minimumMinutes นาที',
      );
  String get urgentNegotiationInProgressTitle =>
      _s('진행 중인 긴급 협상', 'กำลังเจรจากับงานด่วน');
  String get urgentNegotiationLeaveMessage => _s(
        '진행 중인 긴급 협상이 있습니다. 그래도 나가시겠습니까?\n'
            '서버의 잠금은 즉시 해제되지 않으며, ETA를 제출하지 않으면 '
            '3분 이내 자동으로 취소됩니다.',
        'กำลังเจรจางานด่วนอยู่ ต้องการออกจากหน้านี้หรือไม่?\n'
            'ระบบยังไม่ปลดล็อกทันที หากไม่ส่ง ETA '
            'จะถูกยกเลิกอัตโนมัติภายใน 3 นาที',
      );
  String get continueNegotiation => _s('계속 진행', 'ดำเนินการต่อ');

  // Urgent awaiting banner
  String get customerConfirmedAssigned => _s(
        '고객이 확인했습니다. 예약이 배정되었습니다.',
        'ลูกค้ายืนยันแล้ว มอบหมายงานเรียบร้อย',
      );
  String get roundEndChecking =>
      _s('라운드 종료 확인 중...', 'กำลังตรวจสอบการจบรอบ...');
  String awaitingCustomerConfirmation(String countdown) => _s(
        '고객 확인 대기 중 (남은 시간 $countdown)',
        'รอลูกค้ายืนยัน (เวลาเหลือ $countdown)',
      );

  // Booking list
  String get todayAssignmentsTitle =>
      _s('오늘의 배정 예약', 'งานที่มอบหมายวันนี้');
  String get noAssignmentsToday =>
      _s('오늘 배정된 예약이 없습니다.', 'วันนี้ยังไม่มีงานที่มอบหมาย');
  String get noTripScheduleInfo =>
      _s('운행 시각 정보 없음', 'ไม่มีข้อมูลเวลาเดินทาง');
  String standbyReferenceLabel(String reference) =>
      _s('대기 기준 $reference', 'เวลารอ $reference');
  String expectedIncomeLabel(String amount) =>
      _s('예상 수입 $amount', 'รายได้โดยประมาณ $amount');

  // Booking detail
  String get bookingDetailTitle => _s('예약 상세', 'รายละเอียดงาน');
  String get acceptBookingTitle => _s('예약 수락', 'รับงาน');
  String get acceptBookingContent =>
      _s('이 예약을 수락하시겠습니까?', 'ต้องการรับงานนี้หรือไม่?');
  String get acceptBooking => _s('예약 수락', 'รับงาน');
  String get tripEndedMessage =>
      _s('운행이 종료되었습니다.', 'จบการเดินทางแล้ว');
  String actionCompleted(String actionLabel) =>
      _s('$actionLabel 처리가 완료되었습니다.', '$actionLabel สำเร็จแล้ว');
  String get assignmentReleasedSuccess =>
      _s('배정을 반납했습니다.', 'คืนงานแล้ว');
  String get cannotOpenMapsApp =>
      _s('지도 앱을 열 수 없습니다.', 'เปิดแอปแผนที่ไม่ได้');
  String get takePhoto => _s('사진 촬영', 'ถ่ายรูป');
  String get pickFromGallery =>
      _s('갤러리에서 선택', 'เลือกจากแกลเลอรี');
  String get nameSignPhotoUploaded =>
      _s('피켓 사진이 업로드되었습니다.', 'อัปโหลดรูปป้ายชื่อแล้ว');
  String get nameSignPhotoReplaced =>
      _s('피켓 사진이 교체되었습니다.', 'เปลี่ยนรูปป้ายชื่อแล้ว');
  String get bookingNoLongerVisible => _s(
        '이 예약은 더 이상 배정 내역에서 확인할 수 없습니다.',
        'ไม่พบงานนี้ในรายการที่มอบหมายแล้ว',
      );
  String get backToList => _s('목록으로 돌아가기', 'กลับไปรายการ');
  String get standbyConfirmPending =>
      _s('대기 확정 대기', 'รอการยืนยันรอรับ');
  String standbyAllowedFrom(String datetime) =>
      _s('$datetime부터 대기 확정 가능', 'ยืนยันรอรับได้ตั้งแต่ $datetime');
  String get sectionTripInfo => _s('운행 정보', 'ข้อมูลการเดินทาง');
  String get labelPickup => _s('픽업', 'รับผู้โดยสาร');
  String get labelOrigin => _s('출발지', 'จุดเริ่มต้น');
  String get labelDestination => _s('목적지', 'จุดหมาย');
  String get sectionCustomerAndPassengers =>
      _s('고객 및 탑승 정보', 'ข้อมูลลูกค้าและผู้โดยสาร');
  String get labelCustomerName => _s('고객명', 'ชื่อลูกค้า');
  String get labelTotalPassengers => _s('총 인원', 'จำนวนผู้โดยสาร');
  String get labelPassengerComposition => _s('구성', 'รายละเอียดผู้โดยสาร');
  String get labelLuggage => _s('수하물', 'สัมภาระ');
  String get labelNameboard => _s('네임보드', 'ป้ายชื่อ');
  String get nameboardRequested => _s('요청됨', 'มีคำขอ');
  String get sectionFlightAndVehicle =>
      _s('항공편 및 차량', 'เที่ยวบินและรถ');
  String get labelFlight => _s('항공편', 'เที่ยวบิน');
  String get labelFlightStatus => _s('항공편 상태', 'สถานะเที่ยวบิน');
  String get labelEstimatedArrival => _s('도착 예정', 'เวลาถึงโดยประมาณ');
  String get labelDelay => _s('지연', 'ล่าช้า');
  String delayMinutes(int minutes) => _s('$minutes분', '$minutes นาที');
  String get labelVehicle => _s('차량', 'รถ');
  String get sectionAmountInfo => _s('금액 정보', 'ข้อมูลค่าใช้จ่าย');
  String get labelCustomerPaymentAmount =>
      _s('고객 결제 금액', 'ยอดที่ลูกค้าจ่าย');
  String get labelCompanyCommission =>
      _s('회사 수수료', 'ค่าคอมมิชชันบริษัท');
  String get labelDriverExpectedIncome =>
      _s('기사 예상 수입', 'รายได้โดยประมาณของคนขับ');
  String get sectionDriverNotes =>
      _s('기사 참고 사항', 'หมายเหตุสำหรับคนขับ');
  String get labelCustomerRequest =>
      _s('고객 요청', 'คำขอจากลูกค้า');
  String get meetingPlaceGate3WithNameSign => _s(
        '미팅 장소: 3번 게이트 (피켓 요청됨)',
        'จุดนัดพบ: ประตู 3 (มีป้ายชื่อ)',
      );
  String get meetingPlaceGate7 =>
      _s('미팅 장소: 7번 게이트', 'จุดนัดพบ: ประตู 7');
  String get submittedNameSignPhoto =>
      _s('제출된 피켓 사진', 'รูปป้ายชื่อที่ส่งแล้ว');
  String get submitNameSignPhoto =>
      _s('피켓 사진 제출', 'ส่งรูปป้ายชื่อ');
  String nameSignTextLabel(String text) =>
      _s('피켓 문구: $text', 'ข้อความป้ายชื่อ: $text');
  String get recommendPhotoAfterAirportArrival => _s(
        '공항 도착 후 촬영을 권장합니다.',
        'แนะนำให้ถ่ายหลังถึงสนามบิน',
      );
  String get retakeOrReplacePhoto =>
      _s('다시 촬영/교체', 'ถ่ายใหม่/เปลี่ยนรูป');
  String get uploadNameSignPhoto =>
      _s('피켓 사진 업로드', 'อัปโหลดรูปป้ายชื่อ');
  String get viewSubmittedNameSignPhoto =>
      _s('제출된 피켓 사진 보기', 'ดูรูปป้ายชื่อที่ส่งแล้ว');
  String get viewOnMap => _s('지도에서 보기', 'ดูบนแผนที่');
  String get noLocationInfo => _s('위치 정보 없음', 'ไม่มีข้อมูลตำแหน่ง');

  // Trip actions
  String get tripActionStartRouteLabel =>
      _s('운행 시작', 'เริ่มเดินทาง');
  String get tripActionStartRouteConfirm =>
      _s('운행을 시작하시겠습니까?', 'ต้องการเริ่มเดินทางหรือไม่?');
  String get tripActionArriveLabel =>
      _s('도착 확인', 'ยืนยันถึงจุดรับ');
  String get tripActionArriveConfirm => _s(
        '픽업 장소 도착을 확인하시겠습니까?',
        'ยืนยันว่าถึงจุดรับแล้วหรือไม่?',
      );
  String get tripActionPickedUpLabel =>
      _s('탑승 확인', 'ยืนยันผู้โดยสารขึ้นรถ');
  String get tripActionPickedUpConfirm =>
      _s('고객 탑승을 확인하시겠습니까?', 'ยืนยันว่าลูกค้าขึ้นรถแล้วหรือไม่?');
  String get tripActionEndTripLabel =>
      _s('운행 종료', 'จบการเดินทาง');
  String get tripActionEndTripConfirm =>
      _s('운행을 종료하시겠습니까?', 'ต้องการจบการเดินทางหรือไม่?');

  // Name sign upload errors
  String get nameSignValidationError => _s(
        '피켓 사진과 현재 예약 상태를 다시 확인해 주세요.',
        'ตรวจสอบรูปป้ายชื่อและสถานะงานอีกครั้ง',
      );
  String get nameSignInvalidFileType => _s(
        'JPG, JPEG, PNG, WEBP 사진만 업로드할 수 있습니다.',
        'อัปโหลดได้เฉพาะ JPG, JPEG, PNG, WEBP',
      );
  String get nameSignFileTooLarge => _s(
        '파일 크기가 너무 큽니다. 더 작은 사진을 선택해 주세요.',
        'ไฟล์ใหญ่เกินไป กรุณาเลือกรูปที่เล็กกว่า',
      );
  String get nameSignBookingNotFound =>
      _s('예약 정보를 찾을 수 없습니다.', 'ไม่พบข้อมูลงาน');
  String get nameSignForbidden => _s(
        '이 예약의 피켓 사진을 업로드할 권한이 없습니다.',
        'ไม่มีสิทธิ์อัปโหลดรูปป้ายชื่อสำหรับงานนี้',
      );

  // Release assignment
  String get releaseAssignmentTitle => _s('배정 반납', 'คืนงาน');
  String get releaseAssignment => _s('배정 반납', 'คืนงาน');
  String get releaseAssignmentTooltip => _s('배정 반납', 'คืนงาน');
  String get releaseBeforeAcceptHint => _s(
        '수락 전에도 배정을 반납할 수 있습니다.',
        'คืนงานได้แม้ยังไม่กดรับ',
      );
  String get assignmentHandlingTitle =>
      _s('배정 처리', 'จัดการงานที่มอบหมาย');
  String get acceptOrReleaseHint => _s(
        '예약을 수락하거나 배정을 반납할 수 있습니다.',
        'รับงานหรือคืนงานได้',
      );
  String get releasePastDeadlineEmergencyOnly => _s(
        '일반 반납 가능 시간이 지났습니다. 긴급 사유로만 반납할 수 있습니다.',
        'เลยเวลาคืนงานปกติแล้ว คืนได้เฉพาะกรณีฉุกเฉิน',
      );
  String get releaseDeadlinePassed =>
      _s('배정 반납 가능 시간이 지났습니다.', 'เลยเวลาคืนงานแล้ว');
  String get emergencyReleaseOnlyNotice => _s(
        '일반 반납 가능 시간이 지나 긴급 사유만 선택할 수 있습니다.',
        'เลยเวลาคืนงานปกติแล้ว เลือกได้เฉพาะเหตุฉุกเฉิน',
      );
  String get releaseReasonDetailLabel =>
      _s('상세 사유', 'รายละเอียดเหตุผล');
  String get releaseReasonDetailHint =>
      _s('3자 이상 입력해 주세요.', 'กรอกอย่างน้อย 3 ตัวอักษร');
  String get releaseConfirm => _s('반납하기', 'คืนงาน');
  String get releaseReasonVehicleBreakdown =>
      _s('차량 고장', 'รถเสีย');
  String get releaseReasonAccident => _s('사고', 'อุบัติเหตุ');
  String get releaseReasonDriverIllness =>
      _s('기사 질병', 'คนขับป่วย');
  String get releaseReasonFamilyEmergency =>
      _s('가족 긴급 상황', 'ครอบครัวฉุกเฉิน');
  String get releaseReasonScheduleConflict =>
      _s('일정 충돌', 'ตารางงานทับซ้อน');
  String get releaseReasonLocationTooFar =>
      _s('거리가 너무 멂', 'ระยะทางไกลเกินไป');
  String get releaseReasonOther => _s('기타', 'อื่นๆ');
  String get releaseErrorTripAlreadyStarted => _s(
        '운행이 시작되어 배정을 반납할 수 없습니다.',
        'เริ่มเดินทางแล้ว จึงคืนงานไม่ได้',
      );
  String get releaseErrorNoActiveAssignment => _s(
        '활성 배정이 없어 반납할 수 없습니다.',
        'ไม่มีงานที่มอบหมายอยู่ จึงคืนไม่ได้',
      );
  String get releaseErrorNotAssignedDriver => _s(
        '현재 기사에게 배정된 예약이 아닙니다.',
        'งานนี้ไม่ได้มอบหมายให้คุณ',
      );
  String get releaseErrorBookingTerminalStatus => _s(
        '종료된 예약은 반납할 수 없습니다.',
        'งานที่จบแล้วคืนไม่ได้',
      );
  String get releaseErrorInvalidPickupTime => _s(
        '픽업 시간을 확인할 수 없어 반납할 수 없습니다.',
        'ตรวจสอบเวลารับไม่ได้ จึงคืนงานไม่ได้',
      );
  String get releaseErrorWithinTwoHours =>
      _s('일반 반납 가능 시간이 지났습니다.', 'เลยเวลาคืนงานปกติแล้ว');
  String get releaseErrorGeneric => _s(
        '현재 이 배정을 반납할 수 없습니다.',
        'ตอนนี้คืนงานนี้ไม่ได้',
      );

  // Booking accept controller
  String get alreadyAcceptingBooking =>
      _s('이미 예약 수락을 처리 중입니다.', 'กำลังรับงานอยู่แล้ว');
  String get bookingAccepted => _s('예약을 수락했습니다.', 'รับงานแล้ว');
  String get sessionExpiredLoginAgain =>
      _s('로그인이 만료되었습니다. 다시 로그인해 주세요.', 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
  String get bookingNotFoundListRefreshed => _s(
        '예약 정보를 찾을 수 없습니다. 예약 목록을 새로고침했습니다.',
        'ไม่พบข้อมูลงาน รีเฟรชรายการแล้ว',
      );
  String get bookingStatusChangedRefresh => _s(
        '예약 상태가 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
        'สถานะงานเปลี่ยนแล้ว กรุณาตรวจสอบข้อมูลล่าสุด',
      );
  String get acceptResultUncertainRefresh => _s(
        '예약 처리 결과를 확인하지 못했습니다. 예약 상태를 새로고침한 후 다시 확인해 주세요.',
        'ยืนยันผลการรับงานไม่ได้ กรุณารีเฟรชแล้วลองอีกครั้ง',
      );
  String get bookingNotYetAcceptedRetry => _s(
        '예약이 아직 수락되지 않았습니다. 상태를 확인한 뒤 다시 시도해 주세요.',
        'ยังรับงานไม่สำเร็จ ตรวจสอบสถานะแล้วลองใหม่',
      );

  // Booking status labels
  String get statusPending => _s('접수 대기', 'รอรับเรื่อง');
  String get statusOpen => _s('배차 대기', 'รอจัดรถ');
  String get statusConfirmed => _s('예약 확정', 'ยืนยันงานแล้ว');
  String get statusDriverAssigned =>
      _s('기사 배정', 'มอบหมายคนขับแล้ว');
  String get statusOnRoute => _s('이동 중', 'กำลังเดินทาง');
  String get statusDriverArrived =>
      _s('기사 도착', 'คนขับถึงแล้ว');
  String get statusPickedUp => _s('고객 탑승', 'ลูกค้าขึ้นรถแล้ว');
  String get statusSettlementPending =>
      _s('정산 대기', 'รอชำระเงิน');
  String get statusCompleted => _s('운행 완료', 'เดินทางเสร็จแล้ว');
  String get statusCancelled => _s('예약 취소', 'ยกเลิกงาน');
  String get statusNoShow => _s('노쇼', 'ไม่มาตามนัด');
  String get statusUnknown => _s('알 수 없는 상태', 'สถานะไม่ทราบ');
  String bookingStatusSemantic(String statusLabel) =>
      _s('예약 상태 $statusLabel', 'สถานะงาน $statusLabel');

  // Passenger / luggage breakdown
  String adultsCount(int count) => _s('성인 $count명', 'ผู้ใหญ่ $count คน');
  String childrenCount(int count) => _s('아동 $count명', 'เด็ก $count คน');
  String infantsCount(int count) => _s('유아 $count명', 'ทารก $count คน');
  String carriers20InchCount(int count) =>
      _s('20인치 $count개', 'กระเป๋า 20 นิ้ว $count ใบ');
  String carriers24InchPlusCount(int count) =>
      _s('24인치 이상 $count개', 'กระเป๋า 24 นิ้วขึ้นไป $count ใบ');
  String golfBagsCount(int count) =>
      _s('골프백 $count개', 'กระเป๋ากอล์ฟ $count ใบ');

  // Booking display formatters
  String bookingCreatedAt(int month, int day, int hour, String minuteText) =>
      _s(
        '예약: ${month}월 ${day}일 ${hour}시 $minuteText분',
        'จอง: $day/$month $hour:$minuteText',
      );
  String get assignmentReleasedDefaultMessage => _s(
        '이 예약의 배정이 종료되어 목록으로 돌아갑니다.',
        'งานนี้ถูกคืนแล้ว กลับไปที่รายการ',
      );
  String get assignmentReleasedAdminMessage => _s(
        '관리자에 의해 배정이 취소되어 목록으로 돌아갑니다. 자세한 사항은 고객센터로 문의해주세요.',
        'แอดมินยกเลิกการมอบหมายแล้ว กลับไปที่รายการ หากมีข้อสงสัยติดต่อศูนย์บริการ',
      );

  // Pickup delay banner
  String get pickupPastDueBanner =>
      _s('픽업 시간이 지났습니다.', 'เลยเวลารับแล้ว');
  String pickupPastDueDelayedHoursMinutes(int hours, int minutes) => _s(
        '픽업 시간 $hours시간 $minutes분 경과',
        'เลยเวลารับ ${hours} ชม. $minutes นาที',
      );
  String pickupPastDueDelayedMinutes(int minutes) => _s(
        '픽업 시간 $minutes분 경과',
        'เลยเวลารับ $minutes นาที',
      );

  // Settlement list
  String get settlementTitle => _s('정산', 'การชำระเงิน');
  String get settlementListEmpty =>
      _s('정산 내역이 없습니다.', 'ยังไม่มีรายการชำระเงิน');
  String get customerPaymentAmount =>
      _s('고객 결제액', 'ยอดที่ลูกค้าจ่าย');
  String get driverIncome => _s('기사 수입', 'รายได้คนขับ');
  String nameSignCostIncluded(String amount) => _s(
        '(피켓 비용 -$amount바트 포함)',
        '(รวมค่าป้ายชื่อ -$amount บาท)',
      );
  String get commissionFee => _s('수수료', 'ค่าคอมมิชชัน');
  String dueAtLabel(String dueAt) => _s('마감: $dueAt', 'ครบกำหนด: $dueAt');
  String get amountUnavailable =>
      _s('금액 정보 없음', 'ไม่มีข้อมูลจำนวนเงิน');

  // Settlement status labels
  String get settlementStatusNotDueYet =>
      _s('정산 대상 아님', 'ยังไม่ถึงกำหนดชำระ');
  String get settlementStatusDue => _s('송금 필요', 'ต้องโอนเงิน');
  String get settlementStatusReceiptSubmitted =>
      _s('승인 대기 중', 'รออนุมัติ');
  String get settlementStatusOverdue =>
      _s('기한 초과', 'เลยกำหนด');
  String get settlementStatusRejected => _s('반려됨', 'ถูกปฏิเสธ');
  String get settlementStatusApproved =>
      _s('정산 완료', 'ชำระเงินเสร็จแล้ว');
  String get settlementStatusWaived => _s('면제', 'ยกเว้น');
  String get settlementStatusUnknown =>
      _s('상태 확인 필요', 'ต้องตรวจสอบสถานะ');

  // Settlement detail
  String get completeSettlementForNewCalls => _s(
        '이 정산을 완료해야 새 콜을 받을 수 있습니다.',
        'ต้องชำระเงินรายการนี้ก่อนรับงานใหม่',
      );
  String get settlementStatusLabel =>
      _s('정산 상태', 'สถานะการชำระเงิน');
  String get companyCommission =>
      _s('회사 커미션', 'ค่าคอมมิชชันบริษัท');
  String get customerPaymentTotal =>
      _s('고객 결제 총액', 'ยอดรวมที่ลูกค้าจ่าย');
  String get driverExpectedIncome =>
      _s('기사 예상수입', 'รายได้โดยประมาณของคนขับ');
  String receiptStatusRow(String status) =>
      _s('송금증 상태', 'สถานะสลิปโอนเงิน');
  String get dueDateLabel => _s('마감', 'ครบกำหนด');
  String get rejectionReasonLabel =>
      _s('반려 사유', 'เหตุผลที่ปฏิเสธ');
  String get approvalMethodManual =>
      _s('관리자 수동 승인', 'อนุมัติโดยแอดมิน');
  String get submittedReceiptTitle =>
      _s('제출한 송금증', 'สลิปที่ส่งแล้ว');
  String get receiptFileLoadFailed => _s(
        '송금증 파일을 불러올 수 없습니다.',
        'โหลดไฟล์สลิปไม่ได้',
      );
  String get depositInstructionsTitle =>
      _s('입금 안내', 'ข้อมูลการโอนเงิน');
  String get bankLabel => _s('은행', 'ธนาคาร');
  String get accountHolderLabel => _s('예금주', 'ชื่อบัญชี');
  String get accountNumberLabel => _s('계좌번호', 'เลขบัญชี');
  String get qrImageLoadFailed =>
      _s('QR 이미지를 불러올 수 없습니다.', 'โหลด QR ไม่ได้');
  String get fileDownloaded =>
      _s('파일을 다운로드했습니다.', 'ดาวน์โหลดไฟล์แล้ว');
  String get receiptReupload =>
      _s('송금증 재업로드', 'อัปโหลดสลิปใหม่');
  String get receiptUpload =>
      _s('송금증 업로드', 'อัปโหลดสลิป');
  String get receiptPendingResubmit =>
      _s('승인 대기 중 · 다시 제출', 'รออนุมัติ · ส่งใหม่');
  String get settlementCompleted =>
      _s('정산 처리가 완료되었습니다.', 'ชำระเงินเสร็จแล้ว');
  String get noFurtherActionRequired =>
      _s('추가 작업이 필요하지 않습니다.', 'ไม่ต้องทำอะไรเพิ่ม');

  // Receipt upload
  String get receiptUploadUnknownError => _s(
        '송금증 업로드 중 알 수 없는 오류가 발생했습니다.',
        'เกิดข้อผิดพลาดขณะอัปโหลดสลิป',
      );
  String get receiptUploadTitle =>
      _s('송금증 업로드', 'อัปโหลดสลิป');
  String get receiptFileTypesHint =>
      _s('JPG, PNG, PDF 파일을 선택해 주세요.', 'เลือกไฟล์ JPG, PNG หรือ PDF');
  String get selectFile => _s('파일 선택', 'เลือกไฟล์');
  String get selectDifferentFile =>
      _s('다른 파일 선택', 'เลือกไฟล์อื่น');
  String get settlementUploadValidationError => _s(
        '입력값을 확인해 주세요. 송금증 파일이 필요합니다.',
        'ตรวจสอบข้อมูลอีกครั้ง ต้องแนบไฟล์สลิป',
      );
  String get settlementUploadInvalidFileType => _s(
        '지원하지 않는 파일 형식입니다. JPG, PNG, PDF만 업로드할 수 있습니다.',
        'รองรับเฉพาะ JPG, PNG, PDF',
      );
  String get settlementUploadFileTooLarge => _s(
        '파일 크기가 너무 큽니다. 더 작은 송금증 파일을 선택해 주세요.',
        'ไฟล์ใหญ่เกินไป กรุณาเลือกสลิปที่เล็กกว่า',
      );
  String get settlementUploadNotFound => _s(
        '정산 정보를 찾을 수 없습니다. 목록을 새로고침해 주세요.',
        'ไม่พบข้อมูลการชำระเงิน กรุณารีเฟรชรายการ',
      );
  String get settlementUploadAlreadyApproved => _s(
        '이미 승인된 정산은 송금증을 변경할 수 없습니다.',
        'รายการที่อนุมัติแล้วเปลี่ยนสลิปไม่ได้',
      );

  // Account page
  String get accountTitle => _s('계정', 'บัญชี');
  String get noReviewsYet => _s('아직 리뷰 없음', 'ยังไม่มีรีวิว');
  String ratingSummary(String rating, int reviewCount) => _s(
        '$rating · 리뷰 $reviewCount개',
        '$rating · $reviewCount รีวิว',
      );
  String get editProfile => _s('프로필 수정', 'แก้ไขโปรไฟล์');
  String get manageVehicles => _s('차량 관리', 'จัดการรถ');
  String get primaryVehicle => _s('주 차량', 'รถหลัก');
  String get noPrimaryVehicleRegistered => _s(
        '등록된 주 차량이 없습니다.',
        'ยังไม่ได้ลงทะเบียนรถหลัก',
      );

  // Profile edit
  String get profileEditTitle => _s('프로필 수정', 'แก้ไขโปรไฟล์');
  String get replaceProfilePhoto =>
      _s('프로필 사진 교체', 'เปลี่ยนรูปโปรไฟล์');
  String get name => _s('이름', 'ชื่อ');
  String get phone => _s('전화번호', 'เบอร์โทร');
  String get emailReadOnly =>
      _s('이메일 (읽기 전용)', 'อีเมล (อ่านอย่างเดียว)');
  String get vehicleType => _s('차종', 'ประเภทรถ');
  String get model => _s('모델', 'รุ่น');
  String get vehiclePlateNumber => _s('차량 번호', 'ทะเบียนรถ');
  String get color => _s('색상', 'สี');
  String get year => _s('연식', 'ปีรถ');
  String get vehiclePhotoUnavailable => _s(
        '등록된 차량 사진이 없거나 아직 승인되지 않았습니다.',
        'ยังไม่มีรูปรถหรือยังไม่ได้รับการอนุมัติ',
      );
  String get replaceVehiclePhoto =>
      _s('차량 사진 교체', 'เปลี่ยนรูปรถ');
  String get nameLengthValidation =>
      _s('이름은 1~100자로 입력해 주세요.', 'ชื่อต้องมี 1–100 ตัวอักษร');
  String get phoneLengthValidation =>
      _s('전화번호는 8~20자로 입력해 주세요.', 'เบอร์โทรต้องมี 8–20 ตัวอักษร');
  String get modelLengthValidation =>
      _s('차량 모델은 100자 이내로 입력해 주세요.', 'รุ่นรถต้องไม่เกิน 100 ตัวอักษร');
  String get colorLengthValidation =>
      _s('차량 색상은 30자 이내로 입력해 주세요.', 'สีรถต้องไม่เกิน 30 ตัวอักษร');
  String get plateRequiredValidation =>
      _s('차량 번호를 입력해 주세요.', 'กรุณากรอกทะเบียนรถ');
  String get plateLengthValidation =>
      _s('차량 번호는 20자 이내로 입력해 주세요.', 'ทะเบียนรถต้องไม่เกิน 20 ตัวอักษร');
  String yearRangeValidation(int minYear, int maxYear) => _s(
        '연식은 ${minYear}년부터 $maxYear년 사이로 입력해 주세요.',
        'ปีรถต้องอยู่ระหว่าง $minYear–$maxYear',
      );
  String get noChangesToSave =>
      _s('변경된 내용이 없습니다.', 'ไม่มีการเปลี่ยนแปลง');
  String get profileSaved =>
      _s('프로필이 저장되었습니다.', 'บันทึกโปรไฟล์แล้ว');
  String get profilePhotoChanged =>
      _s('프로필 사진이 변경되었습니다.', 'เปลี่ยนรูปโปรไฟล์แล้ว');
  String get vehiclePhotoChanged =>
      _s('차량 사진이 변경되었습니다.', 'เปลี่ยนรูปรถแล้ว');
  String get noApprovedApplicationForVehiclePhoto => _s(
        '승인된 기사 지원서가 없어 차량 사진을 변경할 수 없습니다.',
        'ยังไม่มีใบสมัครที่อนุมัติ จึงเปลี่ยนรูปรถไม่ได้',
      );

  // Vehicle list
  String get vehicleManagementTitle =>
      _s('차량 관리', 'จัดการรถ');
  String get addVehicle => _s('차량 추가', 'เพิ่มรถ');
  String get noRegisteredVehicles =>
      _s('등록된 차량이 없습니다.', 'ยังไม่มีรถที่ลงทะเบียน');
  String get approvalPending => _s('승인 대기', 'รออนุมัติ');
  String get approvalRejected => _s('승인 거절', 'ไม่อนุมัติ');
  String get approvalComplete => _s('승인 완료', 'อนุมัติแล้ว');
  String get primaryVehicleChip => _s('주 차량', 'รถหลัก');
  String vehicleRejectionReason(String reason) =>
      _s('거절 사유: $reason', 'เหตุผลที่ปฏิเสธ: $reason');

  // Vehicle add
  String get addVehicleTitle => _s('차량 추가', 'เพิ่มรถ');
  String get modelNameOptional =>
      _s('모델명 (선택)', 'รุ่น (ไม่บังคับ)');
  String get colorOptional => _s('색상 (선택)', 'สี (ไม่บังคับ)');
  String vehiclePhotosProgress(int count) =>
      _s('차량 사진 ($count/3~6)', 'รูปรถ ($count/3–6)');
  String get selectVehiclePhotos =>
      _s('차량 사진 선택', 'เลือกรูปรถ');
  String get clearAllVehiclePhotos =>
      _s('차량 사진 전체 삭제', 'ลบรูปรถทั้งหมด');
  String get insuranceCertificate =>
      _s('보험증서', 'ใบประกัน');
  String get vehicleRegistrationDoc =>
      _s('차량등록증', 'เล่มทะเบียนรถ');
  String get requiredFileNotSelected =>
      _s('필수 파일을 선택해 주세요.', 'กรุณาเลือกไฟล์ที่จำเป็น');
  String get submitRegistration =>
      _s('등록 신청', 'ส่งคำขอลงทะเบียน');
  String get vehicleRegisteredPendingApproval => _s(
        '차량이 등록되었습니다. 승인 대기 중입니다.',
        'ลงทะเบียนรถแล้ว รออนุมัติ',
      );
  String get plateAlreadyRegistered =>
      _s('이미 등록된 차량 번호입니다.', 'ทะเบียนรถนี้ลงทะเบียนแล้ว');

  // Driver application
  String get driverApplicationTitle =>
      _s('기사 등록 신청', 'สมัครคนขับ');
  String get driverApplicationSectionAccount =>
      _s('계정 정보', 'ข้อมูลบัญชี');
  String get driverApplicationSectionDriverInfo =>
      _s('기사/차량 정보', 'ข้อมูลคนขับและรถ');
  String get driverApplicationSectionDocuments =>
      _s('문서 및 동의', 'เอกสารและการยินยอม');
  String get driverApplicationFullName => _s('이름', 'ชื่อ');
  String get driverApplicationPhone => _s('전화번호', 'เบอร์โทรศัพท์');
  String get driverApplicationPasswordConfirm =>
      _s('비밀번호 확인', 'ยืนยันรหัสผ่าน');
  String get driverApplicationLicenseNumber =>
      _s('면허번호', 'เลขที่ใบขับขี่');
  String get driverApplicationLicenseCountry =>
      _s('면허 발급국', 'ประเทศที่ออกใบขับขี่');
  String get driverApplicationLicenseExpiry =>
      _s('면허 만료일', 'วันหมดอายุใบขับขี่');
  String get driverApplicationLicenseExpiryPicker =>
      _s('날짜 선택', 'เลือกวันที่');
  String get driverApplicationBankName => _s('은행명', 'ชื่อธนาคาร');
  String get driverApplicationBankAccountNumber =>
      _s('계좌번호', 'เลขที่บัญชี');
  String get driverApplicationBankAccountHolder =>
      _s('예금주', 'ชื่อบัญชี');
  String get driverApplicationVehicleMake => _s('제조사', 'ยี่ห้อ');
  String get driverApplicationVehicleModel => _s('모델', 'รุ่น');
  String get driverApplicationVehicleYear => _s('연식', 'ปีรถ');
  String get driverApplicationVehicleColor => _s('색상', 'สี');
  String get driverApplicationServiceAreas =>
      _s('운행 지역', 'พื้นที่ให้บริการ');
  String get driverApplicationServiceAreasHint =>
      _s('방콕, 파타야 (쉼표로 구분)', 'กรุงเทพ, พัทยา (คั่นด้วยจุลภาค)');
  String get driverApplicationLineId => _s('LINE ID', 'LINE ID');
  String get driverApplicationLineQr =>
      _s('LINE QR 코드', 'QR Code LINE');
  String get driverApplicationTaxCertificate =>
      _s('세금납부증명서', 'หลักฐานการชำระภาษี');
  String get driverApplicationPersonalConsent => _s(
        '개인정보 수집 및 검토에 동의합니다.',
        'ฉันยินยอมให้เก็บและตรวจสอบข้อมูลส่วนบุคคล',
      );
  String get driverApplicationTermsConsent => _s(
        '기사 심사 및 운영 규정에 동의합니다.',
        'ฉันยอมรับการคัดกรองคนขับและกฎการให้บริการ',
      );
  String get driverApplicationFalseInfoNotice => _s(
        '허위 정보 제출 시 승인이 취소될 수 있습니다.',
        'ข้อมูลเท็จอาจทำให้การอนุมัติถูกยกเลิก',
      );
  String get driverApplicationSubmit =>
      _s('가입 요청', 'ส่งคำขอสมัคร');
  String get driverApplicationPasswordMin =>
      _s('비밀번호는 6자 이상이어야 합니다.', 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
  String get driverApplicationPasswordMismatch =>
      _s('비밀번호가 일치하지 않습니다.', 'รหัสผ่านไม่ตรงกัน');
  String get driverApplicationConsentRequired =>
      _s('필수 동의가 필요합니다.', 'ต้องยินยอมรายการที่จำเป็น');
  String get driverApplicationServiceAreaRequired => _s(
        '운행 지역을 하나 이상 입력해 주세요.',
        'กรุณากรอกพื้นที่ให้บริการอย่างน้อย 1 รายการ',
      );
  String get driverApplicationVehicleRequired =>
      _s('차량 유형을 선택해 주세요.', 'กรุณาเลือกประเภทรถ');
  String get driverApplicationVehiclePhotoCountError => _s(
        '차량 사진은 3~6장이 필요합니다.',
        'ต้องมีรูปรถ 3-6 รูป',
      );
  String get driverApplicationLicenseExpiryInvalid => _s(
        '면허 만료일 형식이 올바르지 않습니다.',
        'รูปแบบวันหมดอายุใบขับขี่ไม่ถูกต้อง',
      );
  String get driverApplicationLicenseExpiryPast => _s(
        '면허 만료일은 오늘 이후여야 합니다.',
        'วันหมดอายุใบขับขี่ต้องอยู่หลังวันนี้',
      );
  String get driverApplicationVehicleYearInvalid => _s(
        '연식을 1980년부터 현재 연도까지 입력해 주세요.',
        'กรอกปีรถตั้งแต่ 1980 ถึงปีปัจจุบัน',
      );
  String get driverApplicationVehicleTypesLoadError => _s(
        '차량 유형을 불러오지 못했습니다.',
        'โหลดประเภทรถไม่สำเร็จ',
      );
  String get driverApplicationSubmitFailed => _s(
        '가입 신청을 제출하지 못했습니다.',
        'ส่งคำขอสมัครไม่สำเร็จ',
      );
  String get driverApplicationPhoneConflict => _s(
        '이미 등록되었거나 검토 중인 전화번호입니다.',
        'เบอร์โทรนี้ลงทะเบียนหรืออยู่ระหว่างตรวจสอบแล้ว',
      );
  String get driverApplicationPlateConflict => _s(
        '이미 등록되었거나 검토 중인 차량번호입니다.',
        'ทะเบียนรถนี้ลงทะเบียนหรืออยู่ระหว่างตรวจสอบแล้ว',
      );
  String get driverApplicationDuplicateConflict => _s(
        '중복된 가입 신청입니다.',
        'มีใบสมัครซ้ำอยู่แล้ว',
      );
  String get driverApplicationRequiredField =>
      _s('필수 항목을 입력해 주세요.', 'กรุณากรอกข้อมูลที่จำเป็น');
  String get driverApplicationSubmittedMessage => _s(
        '관리자에게 승인 요청 했습니다.',
        'ส่งคำขอให้ผู้ดูแลอนุมัติแล้ว',
      );
  String get driverApplicationLineGroupInstruction => _s(
        '아래 QR 코드를 스캔하여 드라이버 LINE 단체방에 입장하고 가입 신청했다고 알려주세요.',
        'สแกน QR Code ด้านล่างเพื่อเข้ากลุ่ม LINE คนขับ และแจ้งว่าได้ส่งคำขอสมัครแล้ว',
      );
  String driverApplicationNumberLabel(String applicationNumber) => _s(
        '신청번호: $applicationNumber',
        'เลขที่ใบสมัคร: $applicationNumber',
      );
  String get driverApplicationNumberStatusHint => _s(
        '이 번호로 나중에 승인 여부를 확인할 수 있습니다.',
        'คุณสามารถตรวจสอบสถานะการอนุมัติภายหลังด้วยเลขนี้',
      );
  String get driverApplicationBackToLogin =>
      _s('로그인 화면으로 돌아가기', 'กลับไปหน้าเข้าสู่ระบบ');
  String get driverApplicationLineQrUnavailable => _s(
        'LINE 단체방 QR 코드가 준비되면 여기에 표시됩니다.',
        'QR Code LINE จะปรากฏที่นี่เมื่อพร้อมใช้งาน',
      );
  String get driverApplicationStatusTitle =>
      _s('가입 신청 상태', 'สถานะใบสมัคร');
  String get driverApplicationStatusLoading =>
      _s('신청 상태를 확인하는 중...', 'กำลังตรวจสอบสถานะใบสมัคร...');
  String get driverApplicationStatusFailed => _s(
        '신청 상태를 확인하지 못했습니다.',
        'ตรวจสอบสถานะใบสมัครไม่สำเร็จ',
      );
  String get driverApplicationStatusNotFound => _s(
        '신청 정보를 찾을 수 없습니다. 신청번호와 토큰을 확인해 주세요.',
        'ไม่พบข้อมูลใบสมัคร กรุณาตรวจสอบเลขที่ใบสมัครและโทเคน',
      );
  String get driverApplicationStatusManual => _s(
        '신청번호와 상태 토큰 입력',
        'กรอกเลขที่ใบสมัครและโทเคน',
      );
  String get driverApplicationNumberLabelField =>
      _s('신청번호', 'เลขที่ใบสมัคร');
  String get driverApplicationStatusToken =>
      _s('상태 토큰', 'โทเคนสถานะ');
  String get driverApplicationStatusLookup =>
      _s('상태 확인', 'ตรวจสอบสถานะ');
  String get driverApplicationStatusPendingMessage => _s(
        '심사 중입니다. 승인 결과는 LINE 또는 이 화면에서 확인할 수 있습니다.',
        'อยู่ระหว่างตรวจสอบ สามารถตรวจผลอนุมัติผ่าน LINE หรือหน้านี้',
      );
  String get driverApplicationStatusApprovedMessage => _s(
        '승인되었습니다! 로그인해 주세요.',
        'อนุมัติแล้ว! กรุณาเข้าสู่ระบบ',
      );
  String get driverApplicationStatusRejectedTitle =>
      _s('신청이 거절되었습니다', 'ใบสมัครถูกปฏิเสธ');
  String get driverApplicationRejectionReason =>
      _s('거절 사유', 'เหตุผลที่ปฏิเสธ');
  String get driverApplicationResubmit =>
      _s('다시 신청하기', 'สมัครใหม่');
  String get driverApplicationResubmitComingSoon => _s(
        '재신청 기능은 준비 중입니다.',
        'ฟีเจอร์สมัครใหม่อยู่ระหว่างเตรียมการ',
      );
  String get driverApplicationGoToLogin =>
      _s('로그인 화면으로 이동', 'ไปหน้าเข้าสู่ระบบ');
  String get driverApplicationUseManualLookup =>
      _s('다른 정보로 조회', 'ค้นหาด้วยข้อมูลอื่น');
  String get loginSignUp => _s('회원가입', 'สมัครสมาชิก');
  String get loginCheckApplicationStatus =>
      _s('가입 신청 상태 확인', 'ตรวจสอบสถานะใบสมัคร');

  // API errors
  String get errorInvalidCredentials =>
      _s('계정 또는 비밀번호를 확인해 주세요.', 'ตรวจสอบบัญชีหรือรหัสผ่าน');
  String get errorUnauthorized =>
      _s('로그인이 만료되었습니다. 다시 로그인해 주세요.', 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
  String get errorForbidden => _s(
        '예약을 수락할 수 없습니다. 관리자에게 문의해 주세요.',
        'รับงานไม่ได้ กรุณาติดต่อแอดมิน',
      );
  String get errorNotFound =>
      _s('예약 정보를 찾을 수 없습니다.', 'ไม่พบข้อมูลงาน');
  String get errorStandbyTooEarly => _s(
        '아직 대기 확정 시간이 아닙니다. 대기 가능 시간을 확인해 주세요.',
        'ยังไม่ถึงเวลายืนยันรอรับ ตรวจสอบเวลาที่กำหนด',
      );
  String get errorStandbyReferenceTimeMissing => _s(
        '대기 확정 기준 시간을 확인할 수 없습니다. 관리자에게 문의해 주세요.',
        'ตรวจสอบเวลารอรับไม่ได้ กรุณาติดต่อแอดมิน',
      );
  String get errorBookingTimeConflict => _s(
        '기존 운행과 시간이 겹쳐 이 콜을 받을 수 없습니다.',
        'เวลาทับกับงานเดิม รับงานนี้ไม่ได้',
      );
  String get errorAlreadyClaimed => _s(
        '다른 기사가 먼저 이 콜을 배정받았습니다.',
        'มีคนขับรับงานนี้ไปก่อนแล้ว',
      );
  String get errorInvalidStatusTransition => _s(
        '운행 상태가 이미 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
        'สถานะเปลี่ยนแล้ว กรุณาตรวจสอบข้อมูลล่าสุด',
      );
  String get errorReleaseNotAllowed => _s(
        '현재 이 배정을 반납할 수 없습니다.',
        'ตอนนี้คืนงานนี้ไม่ได้',
      );
  String get errorAssignmentAlreadyReleased =>
      _s('이미 반납된 배정입니다.', 'คืนงานไปแล้ว');
  String get errorBookingNotAssigned => _s(
        '현재 기사에게 배정된 예약이 아닙니다.',
        'งานนี้ไม่ได้มอบหมายให้คุณ',
      );
  String get errorValidation =>
      _s('입력 내용을 다시 확인해 주세요.', 'ตรวจสอบข้อมูลที่กรอกอีกครั้ง');
  String get errorInvalidFileType =>
      _s('지원하지 않는 파일 형식입니다.', 'ไม่รองรับไฟล์ประเภทนี้');
  String get errorFileTooLarge => _s(
        '파일 크기가 너무 큽니다. 더 작은 파일을 선택해 주세요.',
        'ไฟล์ใหญ่เกินไป กรุณาเลือกไฟล์ที่เล็กกว่า',
      );
  String get errorSettlementNotFound =>
      _s('정산 정보를 찾을 수 없습니다.', 'ไม่พบข้อมูลการชำระเงิน');
  String get errorReceiptAlreadyApproved => _s(
        '이미 승인된 정산은 송금증을 변경할 수 없습니다.',
        'รายการที่อนุมัติแล้วเปลี่ยนสลิปไม่ได้',
      );
  String get errorDriverNotEligible => _s(
        '미해결 정산이 있어 새 콜을 받을 수 없습니다.',
        'มีการชำระเงินที่ยังไม่เสร็จ จึงรับงานใหม่ไม่ได้',
      );
  String get errorVehiclePlateAlreadyRegistered =>
      _s('이미 등록된 차량 번호입니다.', 'ทะเบียนรถนี้ลงทะเบียนแล้ว');
  String get errorUrgentAlreadyLocked =>
      _s('다른 기사가 이미 수락한 콜입니다.', 'มีคนขับรับงานนี้ไปแล้ว');
  String get errorUrgentNotUrgentBooking => _s(
        '긴급콜로 처리할 수 없는 예약입니다.',
        'งานนี้ไม่ใช่งานด่วน',
      );
  String get errorUrgentNotBroadcasting =>
      _s('더 이상 수락할 수 없는 긴급콜입니다.', 'งานด่วนนี้รับไม่ได้แล้ว');
  String get errorUrgentEtaInvalid =>
      _s('ETA를 1분 이상의 정수로 입력해 주세요.', 'กรอก ETA เป็นตัวเลขเต็มอย่างน้อย 1 นาที');
  String get errorUrgentEtaExceedsPickupWindow => _s(
        '픽업까지 남은 시간보다 짧은 ETA를 입력해 주세요.',
        'ETA ต้องน้อยกว่าเวลาที่เหลือก่อนรับ',
      );
  String get errorUrgentNotLockedDriver =>
      _s('다른 기사에게 넘어간 요청입니다.', 'คำขอนี้ไปอยู่กับคนขับคนอื่นแล้ว');
  String get errorUrgentNegotiationNotFound => _s(
        '긴급 협상 정보를 찾을 수 없습니다.',
        'ไม่พบข้อมูลการเจรจากับงานด่วน',
      );
  String get errorUrgentNotLocked =>
      _s('긴급콜 잠금이 이미 종료되었습니다.', 'ล็อกงานด่วนหมดอายุแล้ว');
  String get errorUrgentEtaExpired =>
      _s('ETA 입력 시간이 만료되었습니다.', 'หมดเวลากรอก ETA แล้ว');
  String get errorUrgentEtaNotFastEnough => _s(
        '이전 제안보다 더 빠른 ETA를 입력해 주세요.',
        'กรอก ETA ให้เร็วกว่าครั้งก่อน',
      );
  String get errorConflict => _s(
        '예약 상태가 변경되었습니다. 최신 정보를 다시 확인해 주세요.',
        'สถานะงานเปลี่ยนแล้ว กรุณาตรวจสอบข้อมูลล่าสุด',
      );
  String get errorUnavailable => _s(
        '서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.',
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบเครือข่าย',
      );
  String get errorTimeout => _s(
        '요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
        'หมดเวลาคำขอ ลองอีกครั้งในไม่ช้า',
      );
  String get errorInvalidResponse =>
      _s('서버 응답을 처리할 수 없습니다.', 'ประมวลผลข้อมูลจากเซิร์ฟเวอร์ไม่ได้');
  String get errorServer => _s(
        '일시적인 오류가 발생했습니다. 다시 시도해 주세요.',
        'เกิดข้อผิดพลาดชั่วคราว ลองอีกครั้ง',
      );
  String get errorConfiguration =>
      _s('이 환경의 API가 설정되지 않았습니다.', 'ยังไม่ได้ตั้งค่า API สำหรับสภาพแวดล้อมนี้');
  String get errorUnknown =>
      _s('알 수 없는 오류가 발생했습니다.', 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales
          .map((item) => item.languageCode)
          .contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final normalized = locale.languageCode == 'ko'
        ? const Locale('ko')
        : const Locale('th');
    return SynchronousFuture(AppLocalizations(normalized));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
