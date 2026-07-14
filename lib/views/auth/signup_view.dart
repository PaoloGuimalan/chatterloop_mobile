import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/auth_api.dart';
import 'package:chatterloop_app/core/requests/jwt_codec.dart';
import 'package:chatterloop_app/models/http_models/response_models.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _month;
  String? _day;
  String? _year;
  String? _gender;
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_agreed) {
      setState(() => _error = "Please agree with the Terms and Conditions.");
      return;
    }
    if (_first.text.trim().isEmpty ||
        _last.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _month == null ||
        _day == null ||
        _year == null ||
        _gender == null) {
      setState(() => _error = "Please complete the fields.");
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = "Password must be at least 8 characters.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    LoginResponse? response = await AuthApi().signupRequest(
      firstName: _first.text.trim(),
      middleName: _middle.text.trim().isEmpty ? null : _middle.text.trim(),
      lastName: _last.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      gender: _gender!.toLowerCase(),
      agreedToTerms: _agreed,
      birthday: int.parse(_day!),
      birthmonth: _months.indexOf(_month!) + 1,
      birthyear: int.parse(_year!),
    );

    if (!mounted) return;

    if (response?.authtoken == null || response?.usertoken == null) {
      setState(() {
        _busy = false;
        _error = "Could not create your account. Please try again.";
      });
      return;
    }

    await ApiClient.instance.writeToken(response!.authtoken);
    Map<String, dynamic>? userResponse = JwtCodec.decode(response.usertoken);

    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount.fromDjangoJwt(userResponse ?? const {},
                allowedModules: response.allowedModules,
                activeEntity: response.activeEntity,
                personalEntityId: response.personalEntityId))));

    setState(() => _busy = false);
    context.go('/verify-email');
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
              constraints: const BoxConstraints(maxWidth: 460),
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
                  Text(
                    'Create your account',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Join the loop in less than a minute.',
                    style: TextStyle(color: p.text2, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                        child: CLField(
                            icon: Icons.person_outline,
                            label: 'First name',
                            controller: _first)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: CLField(
                            label: 'Middle (optional)', controller: _middle)),
                  ]),
                  const SizedBox(height: 13),
                  CLField(
                      icon: Icons.badge_outlined,
                      label: 'Last name',
                      controller: _last),
                  const SizedBox(height: 13),
                  CLField(
                      icon: Icons.alternate_email,
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 13),
                  Text('Birth date',
                      style: TextStyle(
                          color: p.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        flex: 13,
                        child: _dropdown('Month', _month, _months,
                            (v) => setState(() => _month = v))),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 10,
                        child: _dropdown(
                            'Day',
                            _day,
                            List.generate(31, (i) => '${i + 1}'),
                            (v) => setState(() => _day = v))),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 10,
                        child: _dropdown(
                            'Year',
                            _year,
                            List.generate(
                                80, (i) => '${DateTime.now().year - i}'),
                            (v) => setState(() => _year = v))),
                  ]),
                  const SizedBox(height: 13),
                  Text('Gender',
                      style: TextStyle(
                          color: p.text2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: _genderButton('Male', const Color(0xFF49A1F8))),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            _genderButton('Female', const Color(0xFFDB56A4))),
                    const SizedBox(width: 8),
                    Expanded(child: _genderButton('Other', p.brand)),
                  ]),
                  const SizedBox(height: 13),
                  CLField(
                      icon: Icons.lock_outline,
                      label: 'Password',
                      obscure: true,
                      controller: _password),
                  const SizedBox(height: 16),
                  Row(children: [
                    Checkbox(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      activeColor: p.brand,
                    ),
                    Expanded(
                        child: Text(
                      'I agree to the Terms and Conditions',
                      style: TextStyle(color: p.text2, fontSize: 13),
                    )),
                  ]),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!,
                          style: TextStyle(color: p.pink, fontSize: 13)),
                    ),
                  const SizedBox(height: 6),
                  CLBtn(
                    label: _busy ? 'Signing up…' : 'Sign Up',
                    onPressed: _busy ? null : _submit,
                    size: CLBtnSize.lg,
                    block: true,
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Wrap(children: [
                      Text('Already have an account? ',
                          style: TextStyle(color: p.text2, fontSize: 13.5)),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text('Log In',
                            style: TextStyle(
                                color: p.brand,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged) {
    final p = cl(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        border: Border.all(color: p.border),
      ),
      child: DropdownButton<String>(
        value: value,
        hint: Text(label, style: TextStyle(color: p.text3)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: p.surface,
        style: TextStyle(color: p.text, fontSize: 14),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _genderButton(String label, Color activeBg) {
    final p = cl(context);
    final active = _gender == label;
    return InkWell(
      onTap: () => setState(() => _gender = label),
      borderRadius: BorderRadius.circular(CLRadii.sm),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeBg : p.surface,
          border: Border.all(color: active ? Colors.transparent : p.border2),
          borderRadius: BorderRadius.circular(CLRadii.sm),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : p.text2,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
