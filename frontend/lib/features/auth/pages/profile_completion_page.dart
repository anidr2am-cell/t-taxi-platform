import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/auth_controller.dart';
import '../models/social_login_return_context.dart';
import '../services/customer_profile_api_service.dart';
import '../services/social_login_navigation.dart';
import '../widgets/booking_social_login_section.dart';
import '../widgets/profile_completion_form.dart';

class ProfileCompletionRouteArgs {
  const ProfileCompletionRouteArgs({this.returnContext});

  final SocialLoginReturnContext? returnContext;
}

class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({
    super.key,
    this.returnContext,
    this.apiService,
  });

  static const routeName = '/profile/complete';

  final SocialLoginReturnContext? returnContext;
  final CustomerProfileApiService? apiService;

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  late final CustomerProfileApiService _apiService;
  late String _name;
  late String _phone;
  String? _phoneError;
  String? _formError;
  bool _isSubmitting = false;
  bool _fieldsInitialized = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? CustomerProfileApiService();
    _name = '';
    _phone = '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fieldsInitialized) {
      return;
    }
    _fieldsInitialized = true;
    final user = AuthScope.of(context).user;
    _name = user?.name?.trim() ?? '';
    _phone = user?.phone?.trim() ?? '';
  }

  bool _isValid() {
    return _name.trim().isNotEmpty && _phone.trim().length >= 5;
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final name = _name.trim();
    final phone = _phone.trim();

    setState(() {
      _phoneError = null;
      _formError = null;
    });

    if (name.isEmpty) {
      setState(() {
        _formError = l10n.t('profile_completion_name_required');
      });
      return;
    }
    if (phone.length < 5) {
      setState(() {
        _phoneError = l10n.t('profile_completion_phone_required');
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final authController = AuthScope.of(context);
    try {
      await authController.updateCustomerProfile(
        name: name,
        phone: phone,
        apiService: _apiService,
      );
      if (!mounted) {
        return;
      }
      await navigateToSocialLoginReturnContext(
        context,
        authController: authController,
        returnContext: widget.returnContext,
      );
    } on CustomerProfileApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (error.statusCode == 409) {
          _phoneError = error.message.isNotEmpty
              ? error.message
              : l10n.t('profile_completion_phone_duplicate');
        } else {
          _formError = error.message;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _formError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.t('profile_completion_title')),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: AppUi.pagePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.t('profile_completion_body'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppTokens.spaceLg),
                ProfileCompletionForm(
                  initialName: _name,
                  initialPhone: _phone,
                  phoneError: _phoneError,
                  onNameChanged: (value) {
                    setState(() {
                      _name = value;
                      _formError = null;
                    });
                  },
                  onPhoneChanged: (value) {
                    setState(() {
                      _phone = value;
                      _phoneError = null;
                      _formError = null;
                    });
                  },
                ),
                if (_formError != null) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(
                    _formError!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                FilledButton(
                  key: const Key('profile_completion_submit_button'),
                  onPressed: _isSubmitting || !_isValid() ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.t('profile_completion_submit')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
