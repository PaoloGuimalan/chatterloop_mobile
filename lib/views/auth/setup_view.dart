// Post-verification account setup - the mobile counterpart of webapp's
// Setup.tsx. Reached via the router gate (app_router.dart) whenever a
// verified account is not yet `is_complete`: i.e. it's still missing a
// birthdate/gender (Account.is_profile_complete) or has pending terms/
// privacy consents. Collects only what's actually missing, submits it
// (PUT /api/user/me for the profile fields, POST /api/user/policies/accept
// for consent), then optimistically flips isComplete so the gate lets the
// account into the app.

import 'package:chatterloop_app/core/auth/consent_prefs.dart';
import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/store.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/auth_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:chatterloop_app/views/auth/policy_viewer_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _busy = false;
  String? _error;

  DateTime? _birthdate;
  String? _gender; // "male" | "female" | "other"
  bool _agreed = false;

  String? _termsUrl;
  String? _termsContent;
  String? _privacyUrl;
  String? _privacyContent;

  // Which steps this particular account still owes - mirrors webapp's
  // requiredFields (getMissingFields + a "policy" push when pendingConsents
  // is non-empty). Computed once from the account we were gated on.
  late final bool _needBirthdate;
  late final bool _needGender;
  late final bool _needPolicy;

  @override
  void initState() {
    super.initState();
    final user = appStore.state.userAuth.user;
    _needBirthdate = user.birthdate == null;
    _needGender = (user.gender ?? '').isEmpty;
    _needPolicy = user.pendingConsents.isNotEmpty;
    if (_needPolicy) _loadPolicies();
  }

  Future<void> _loadPolicies() async {
    final docs = await AuthApi().getPoliciesRequest();
    if (!mounted) return;
    setState(() {
      for (final d in docs) {
        final type = d['document_type']?.toString();
        final url = d['document_url']?.toString();
        final content = d['content']?.toString();
        if (type == 'terms') {
          _termsUrl = url;
          _termsContent = content;
        }
        if (type == 'privacy') {
          _privacyUrl = url;
          _privacyContent = content;
        }
      }
    });
  }

  int _ageOn(DateTime d) {
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your birthdate',
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  void _openPolicy(String title, String? content, String? url) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PolicyViewerPage(
        title: title,
        content: content,
        url: url,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    ));
  }

  Future<void> _submit() async {
    if (_needBirthdate) {
      if (_birthdate == null) {
        setState(() => _error = 'Please select your birthdate.');
        return;
      }
      if (_ageOn(_birthdate!) < 13) {
        setState(() => _error = 'You must be at least 13 years old.');
        return;
      }
    }
    if (_needGender && _gender == null) {
      setState(() => _error = 'Please select your gender.');
      return;
    }
    if (_needPolicy && !_agreed) {
      setState(() =>
          _error = 'Please agree to the Terms and Conditions and Privacy Policy.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // 1) Complete the profile (birthdate/gender) if either was missing.
    if (_needBirthdate || _needGender) {
      String? birthdateStr;
      if (_needBirthdate && _birthdate != null) {
        final mm = _birthdate!.month.toString().padLeft(2, '0');
        final dd = _birthdate!.day.toString().padLeft(2, '0');
        // Same datetime shape the webapp's Setup sends.
        birthdateStr = '${_birthdate!.year}-$mm-$dd 08:00:00.000 +0800';
      }
      final ok = await AuthApi().completeProfileRequest(
        birthdate: birthdateStr,
        gender: _needGender ? _gender : null,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Could not save your details. Please try again.';
        });
        return;
      }
    }

    // 2) Record consent if there were pending policies.
    if (_needPolicy) {
      final ok = await AuthApi().acceptPoliciesRequest();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Could not record your consent. Please try again.';
        });
        return;
      }
    }

    // Both server writes succeeded - clear the locally-persisted pending
    // consents (so a later restore doesn't re-gate) and optimistically mark
    // the account complete so the router gate advances into the app.
    await ConsentPrefs.save(const []);
    if (!mounted) return;
    final store = StoreProvider.of<AppState>(context);
    final user = store.state.userAuth.user;
    store.dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            user.copyWith(
              isComplete: true,
              pendingConsents: const [],
              gender: _needGender ? _gender : null,
              birthdate: _needBirthdate && _birthdate != null
                  ? UserBirthDate(
                      _birthdate!.month.toString(),
                      _birthdate!.day.toString(),
                      _birthdate!.year.toString())
                  : null,
            ))));

    setState(() => _busy = false);
    context.go('/messages');
  }

  Future<void> _logout() async {
    await ApiClient.instance.clearToken();
    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () => ThemeScope.of(context).toggle(),
                      icon: Icon(
                        Theme.of(context).brightness == Brightness.dark
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        color: p.text2,
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: p.brandSoft),
                      child: Icon(Icons.verified_user_outlined,
                          color: p.brand, size: 30),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Finish setting up',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A few details are needed before you can continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.text2, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (_needBirthdate) ...[
                    _label('Birthdate', p),
                    const SizedBox(height: 6),
                    _tappableField(
                      p,
                      icon: Icons.cake_outlined,
                      text: _birthdate == null
                          ? 'Select your birthdate'
                          : '${_birthdate!.year}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
                      muted: _birthdate == null,
                      onTap: _busy ? null : _pickBirthdate,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_needGender) ...[
                    _label('Gender', p),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _genderChip('Male', 'male', p),
                        const SizedBox(width: 8),
                        _genderChip('Female', 'female', p),
                        const SizedBox(width: 8),
                        _genderChip('Other', 'other', p),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_needPolicy) ...[
                    _consentRow(p),
                    const SizedBox(height: 6),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(color: p.pink, fontSize: 13)),
                    ),
                  const SizedBox(height: 16),
                  CLBtn(
                    label: _busy ? 'Saving…' : 'Continue',
                    onPressed: _busy ? null : _submit,
                    size: CLBtnSize.lg,
                    block: true,
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      children: [
                        Text('Wrong account? ',
                            style: TextStyle(color: p.text2, fontSize: 13.5)),
                        GestureDetector(
                          onTap: _busy ? null : _logout,
                          child: Text('Logout',
                              style: TextStyle(
                                  color: p.brand,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, CLPalette p) => Text(
        text,
        style: TextStyle(
            color: p.text2, fontSize: 13, fontWeight: FontWeight.w600),
      );

  Widget _tappableField(CLPalette p,
      {required IconData icon,
      required String text,
      required bool muted,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.input,
          borderRadius: BorderRadius.circular(CLRadii.sm),
          border: Border.all(color: p.border2, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.text2),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(
                    color: muted ? p.text3 : p.text, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }

  Widget _genderChip(String label, String value, CLPalette p) {
    final selected = _gender == value;
    return Expanded(
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _gender = value),
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? p.brandSoft : p.input,
            borderRadius: BorderRadius.circular(CLRadii.sm),
            border: Border.all(
                color: selected ? p.brand : p.border2, width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? p.brand : p.text,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _consentRow(CLPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: Checkbox(
            value: _agreed,
            onChanged:
                _busy ? null : (v) => setState(() => _agreed = v ?? false),
            activeColor: p.brand,
            visualDensity:
                const VisualDensity(horizontal: -2, vertical: -2),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: p.text2, fontSize: 13.5, height: 1.4),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  _linkSpan(
                      'Terms and Conditions',
                      p,
                      () => _openPolicy(
                          'Terms and Conditions', _termsContent, _termsUrl)),
                  const TextSpan(text: ' and '),
                  _linkSpan(
                      'Privacy Policy',
                      p,
                      () => _openPolicy(
                          'Privacy Policy', _privacyContent, _privacyUrl)),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _linkSpan(String text, CLPalette p, VoidCallback onTap) {
    return TextSpan(
      text: text,
      style: TextStyle(color: p.brand, fontWeight: FontWeight.w700),
      recognizer: (TapGestureRecognizer()..onTap = onTap),
    );
  }
}
