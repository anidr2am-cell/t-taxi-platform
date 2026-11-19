import 'package:flutter/material.dart';
import '../../../widgets/calling_country_picker.dart';
import '../models/admin_calling_codes.dart';

Future<AdminCallingCountry?> showAdminCallingCountryPicker(
  BuildContext context, {
  required String selectedCountryCode,
}) =>
    showCallingCountryPicker(context, selectedCountryCode: selectedCountryCode);
