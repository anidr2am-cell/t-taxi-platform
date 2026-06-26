import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/booking_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/language_selector.dart';
import 'booking_complete_screen.dart';

class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({super.key});

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  int _step = 0;
  bool _loading = false;
  String? _error;

  List<dynamic> _airports = [];
  List<String> _golfRegions = [];
  List<dynamic> _golfCourses = [];
  Map<String, double> _vehiclePrices = {};

  final _flightController = TextEditingController();
  final _specialLuggageController = TextEditingController();
  final _specialRequestsController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _countryController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _customAirport;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      _airports = await ApiService().getAirports();
      _golfRegions = await ApiService().getGolfRegions();
      setState(() {});
    } catch (_) {}
  }

  Future<void> _loadGolfCourses(String region) async {
    _golfCourses = await ApiService().getGolfCourses(region: region);
    setState(() {});
  }

  Future<void> _loadVehicleData(BookingState booking) async {
    setState(() => _loading = true);
    try {
      final recommend = await ApiService().recommendVehicle({
        'adults': booking.adults,
        'children': booking.children,
        'smallCarriers': booking.smallCarriers,
        'largeCarriers': booking.largeCarriers,
        'golfBags': booking.golfBags,
      });
      booking.setVehicleRecommendation(recommend);

      final prices = await ApiService().getVehiclePrices(booking.serviceType!.apiValue);
      _vehiclePrices = {};
      for (final p in prices) {
        _vehiclePrices[p['vehicle_type'] as String] = (p['base_price'] as num).toDouble();
      }

      await _updateTotalPrice(booking);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateTotalPrice(BookingState booking) async {
    if (booking.selectedVehicle == null) return;
    final result = await ApiService().calculatePrice({
      'serviceType': booking.serviceType!.apiValue,
      'selectedVehicle': booking.selectedVehicle,
      'vehicleCount': booking.vehicleCount,
      'nameSignService': booking.nameSignService,
    });
    booking.setTotalPrice((result['totalPrice'] as num).toDouble());
  }

  Future<void> _fetchFlight(BookingState booking) async {
    if (_flightController.text.isEmpty || _selectedDate == null) return;
    setState(() => _loading = true);
    try {
      final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final info = await ApiService().getFlightInfo(_flightController.text, dateStr);
      booking.setRouteInfo(flightNum: _flightController.text, flightInfoData: info);
      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _submitBooking(BookingState booking) async {
    setState(() => _loading = true);
    try {
      booking.setCustomerInfo(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        country: _countryController.text,
        requests: _specialRequestsController.text,
      );
      final result = await ApiService().createReservation(booking.toReservationPayload());
      booking.setCreatedReservation(result);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const BookingCompleteScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  bool _canProceedStep0(BookingState booking) {
    return booking.adults >= 1;
  }

  bool _canProceedStep1(BookingState booking) {
    final type = booking.serviceType!;
    switch (type) {
      case ServiceType.airportPickup:
        return booking.airportCode != null &&
            booking.destinationPlaceId != null &&
            _selectedDate != null &&
            _flightController.text.isNotEmpty;
      case ServiceType.airportDropoff:
        return booking.originPlaceId != null &&
            booking.airportCode != null &&
            _selectedDate != null &&
            _selectedTime != null;
      case ServiceType.cityTransfer:
        return booking.originPlaceId != null &&
            booking.destinationPlaceId != null &&
            _selectedDate != null &&
            _selectedTime != null;
      case ServiceType.golfTransfer:
        return booking.originPlaceId != null &&
            booking.golfRegion != null &&
            booking.golfCourseId != null &&
            booking.destinationPlaceId != null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingState>();
    final locale = context.watch<LocaleState>();
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t(booking.serviceType!.labelKey)),
        actions: const [LanguageSelector()],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / 4),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildStep(booking, locale.languageCode, l10n),
            ),
          ),
          _buildBottomBar(booking, l10n),
        ],
      ),
    );
  }

  Widget _buildStep(BookingState booking, String lang, AppLocalizations l10n) {
    switch (_step) {
      case 0:
        return _buildPassengersStep(booking, l10n);
      case 1:
        return _buildRouteStep(booking, lang, l10n);
      case 2:
        return _buildVehicleStep(booking, l10n);
      case 3:
        return _buildConfirmStep(booking, l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPassengersStep(BookingState booking, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('passengers'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        CounterRow(
          label: l10n.t('adults'),
          value: booking.adults,
          min: 1,
          onChanged: (v) => booking.updatePassengers(adultsVal: v),
        ),
        CounterRow(
          label: l10n.t('children'),
          value: booking.children,
          onChanged: (v) => booking.updatePassengers(childrenVal: v),
        ),
        const SizedBox(height: 24),
        Text(l10n.t('luggage'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        CounterRow(
          label: l10n.t('small_carriers'),
          value: booking.smallCarriers,
          onChanged: (v) => booking.updateLuggage(small: v),
        ),
        CounterRow(
          label: l10n.t('large_carriers'),
          value: booking.largeCarriers,
          onChanged: (v) => booking.updateLuggage(large: v),
        ),
        CounterRow(
          label: l10n.t('golf_bags'),
          value: booking.golfBags,
          onChanged: (v) => booking.updateLuggage(golf: v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _specialLuggageController,
          decoration: InputDecoration(labelText: l10n.t('special_luggage')),
          onChanged: (v) => booking.updateLuggage(special: v),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: booking.nameSignService,
          onChanged: (v) => booking.setNameSignService(v ?? false),
          title: Text(l10n.t('name_sign')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildRouteStep(BookingState booking, String lang, AppLocalizations l10n) {
    final type = booking.serviceType!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (type == ServiceType.airportPickup) ...[
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: l10n.t('airport')),
            items: [
              ..._airports.map((a) => DropdownMenuItem(
                    value: a['code'] as String,
                    child: Text('${a['code']} - ${a['name']}'),
                  )),
              DropdownMenuItem(value: 'OTHER', child: Text(l10n.t('other_airport'))),
            ],
            onChanged: (v) {
              if (v == 'OTHER') {
                booking.setAirportCode('OTHER');
              } else {
                booking.setAirportCode(v);
              }
            },
          ),
          if (booking.airportCode == 'OTHER' || _customAirport != null)
            TextField(
              decoration: InputDecoration(labelText: l10n.t('other_airport')),
              onChanged: (v) {
                _customAirport = v;
                booking.setAirportCode(v);
              },
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _flightController,
            decoration: InputDecoration(labelText: l10n.t('flight_number'), hintText: 'KE651'),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: Text(l10n.t('date')),
            subtitle: Text(_selectedDate?.toString().split(' ').first ?? '-'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                _selectedDate = date;
                booking.setPickupDate('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
                await _fetchFlight(booking);
              }
            },
          ),
          if (booking.flightInfo != null) _buildFlightInfo(booking.flightInfo!),
          const SizedBox(height: 12),
          PlaceSearchField(
            label: l10n.t('destination'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              destId: data['placeId'],
              destAddr: data['address'],
            ),
          ),
        ],
        if (type == ServiceType.airportDropoff) ...[
          PlaceSearchField(
            label: l10n.t('origin'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              originId: data['placeId'],
              originAddr: data['address'],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: l10n.t('airport')),
            items: _airports
                .map((a) => DropdownMenuItem(
                      value: a['code'] as String,
                      child: Text('${a['code']} - ${a['name']}'),
                    ))
                .toList(),
            onChanged: (v) => booking.setAirportCode(v),
          ),
          _buildDateTimePicker(l10n, booking),
        ],
        if (type == ServiceType.cityTransfer) ...[
          PlaceSearchField(
            label: l10n.t('origin'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              originId: data['placeId'],
              originAddr: data['address'],
            ),
          ),
          const SizedBox(height: 12),
          PlaceSearchField(
            label: l10n.t('destination'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              destId: data['placeId'],
              destAddr: data['address'],
            ),
          ),
          _buildDateTimePicker(l10n, booking),
        ],
        if (type == ServiceType.golfTransfer) ...[
          PlaceSearchField(
            label: l10n.t('origin'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              originId: data['placeId'],
              originAddr: data['address'],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: l10n.t('golf_region')),
            items: _golfRegions
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) async {
              if (v != null) {
                booking.setGolfRegion(v);
                await _loadGolfCourses(v);
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            decoration: InputDecoration(labelText: l10n.t('golf_course')),
            items: _golfCourses
                .map((c) => DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(c['name'] as String),
                    ))
                .toList(),
            onChanged: (v) {
              final course = _golfCourses.firstWhere((c) => c['id'] == v);
              booking.setRouteInfo(
                courseId: v,
                courseName: course['name'] as String,
              );
            },
          ),
          const SizedBox(height: 12),
          PlaceSearchField(
            label: l10n.t('destination'),
            languageCode: lang,
            onSelected: (data) => booking.setRouteInfo(
              destId: data['placeId'],
              destAddr: data['address'],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.t('driver_included')),
            value: booking.driverIncluded,
            onChanged: (v) => booking.setDriverIncluded(v),
          ),
        ],
      ],
    );
  }

  Widget _buildDateTimePicker(AppLocalizations l10n, BookingState booking) {
    return Column(
      children: [
        ListTile(
          title: Text(l10n.t('date')),
          subtitle: Text(_selectedDate?.toString().split(' ').first ?? '-'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) {
              _selectedDate = date;
              booking.setPickupDate('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
            }
          },
        ),
        ListTile(
          title: Text(l10n.t('time')),
          subtitle: Text(_selectedTime?.format(context) ?? '-'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (time != null) {
              _selectedTime = time;
              booking.setPickupTime('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
            }
          },
        ),
      ],
    );
  }

  Widget _buildFlightInfo(Map<String, dynamic> info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scheduled: ${info['scheduledArrival'] ?? '-'}'),
            Text('Estimated: ${info['estimatedArrival'] ?? '-'}'),
            Text('Status: ${info['delayStatus'] ?? '-'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleStep(BookingState booking, AppLocalizations l10n) {
    if (booking.recommendedVehicle == null && !_loading) {
      _loadVehicleData(booking);
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    final vehicles = ['SEDAN', 'SUV', 'VIP_SUV', 'VAN'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('select_vehicle'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (booking.recommendedVehicle != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${l10n.t('recommended')}: ${booking.recommendedVehicle}',
              style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 16),
        ...vehicles.map((v) {
          final selectable = booking.selectableVehicles.contains(v);
          final price = _vehiclePrices[v] ?? 0;
          final isSelected = booking.selectedVehicle == v;

          return Card(
            color: isSelected ? Colors.blue.shade50 : (selectable ? null : Colors.grey.shade100),
            child: ListTile(
              enabled: selectable,
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: selectable ? Colors.blue : Colors.grey,
              ),
              title: Text(v),
              subtitle: Text('${price.toStringAsFixed(0)} ${l10n.t('thb')}'),
              onTap: selectable
                  ? () async {
                      booking.selectVehicle(v);
                      await _updateTotalPrice(booking);
                      setState(() {});
                    }
                  : null,
            ),
          );
        }),
        const SizedBox(height: 16),
        Text(
          '${l10n.t('total')}: ${booking.totalPrice.toStringAsFixed(0)} ${l10n.t('thb')}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildConfirmStep(BookingState booking, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('booking_summary'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _summaryRow(l10n.t('service_type'), l10n.t(booking.serviceType!.labelKey)),
        if (booking.originAddress != null) _summaryRow(l10n.t('origin'), booking.originAddress!),
        if (booking.destinationAddress != null) _summaryRow(l10n.t('destination'), booking.destinationAddress!),
        if (booking.airportCode != null) _summaryRow(l10n.t('airport'), booking.airportCode!),
        if (booking.flightNumber != null) _summaryRow(l10n.t('flight_number'), booking.flightNumber!),
        if (booking.pickupDate != null) _summaryRow(l10n.t('date'), booking.pickupDate!),
        if (booking.pickupTime != null) _summaryRow(l10n.t('time'), booking.pickupTime!),
        _summaryRow(l10n.t('passengers'), '${booking.adults} adults, ${booking.children} children'),
        _summaryRow(l10n.t('vehicle'), booking.selectedVehicle ?? '-'),
        _summaryRow(l10n.t('total'), '${booking.totalPrice.toStringAsFixed(0)} ${l10n.t('thb')}'),
        const SizedBox(height: 16),
        TextField(
          controller: _specialRequestsController,
          decoration: InputDecoration(labelText: l10n.t('special_requests')),
          maxLines: 3,
        ),
        const SizedBox(height: 24),
        Text(l10n.t('customer_info'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: _nameController, decoration: InputDecoration(labelText: l10n.t('name'))),
        TextField(controller: _emailController, decoration: InputDecoration(labelText: l10n.t('email'))),
        TextField(controller: _phoneController, decoration: InputDecoration(labelText: l10n.t('phone'))),
        TextField(controller: _countryController, decoration: InputDecoration(labelText: l10n.t('country'))),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BookingState booking, AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: Text(l10n.t('back')),
                ),
              ),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _onNext(booking),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_step == 3 ? l10n.t('confirm') : l10n.t('next')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onNext(BookingState booking) async {
    if (_step == 0 && !_canProceedStep0(booking)) return;
    if (_step == 1 && !_canProceedStep1(booking)) return;
    if (_step == 2 && booking.selectedVehicle == null) return;

    if (_step == 0) {
      setState(() => _step++);
      return;
    }

    if (_step == 1) {
      if (booking.serviceType == ServiceType.airportPickup) {
        booking.setFlightNumber(_flightController.text);
      }
      setState(() => _step++);
      await _loadVehicleData(booking);
      return;
    }

    if (_step == 2) {
      setState(() => _step++);
      return;
    }

    if (_step == 3) {
      if (_nameController.text.isEmpty || _emailController.text.isEmpty || _phoneController.text.isEmpty) {
        setState(() => _error = 'Please fill customer information');
        return;
      }
      await _submitBooking(booking);
    }
  }

  @override
  void dispose() {
    _flightController.dispose();
    _specialLuggageController.dispose();
    _specialRequestsController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    super.dispose();
  }
}
