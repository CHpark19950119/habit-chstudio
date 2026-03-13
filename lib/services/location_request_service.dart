/// LocationRequestService — 레거시 (헤드위그로 대체)
/// app_init 호환을 위해 빈 껍데기 유지
class LocationRequestService {
  static final LocationRequestService _instance =
      LocationRequestService._internal();
  factory LocationRequestService() => _instance;
  LocationRequestService._internal();

  Future<void> init() async {}
}
