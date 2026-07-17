import 'package:chatterloop_app/core/design/theme_provider.dart';
import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/api_client.dart';
import 'package:chatterloop_app/core/requests/auth_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:go_router/go_router.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _digits =
      List<TextEditingController>.generate(6, (_) => TextEditingController());
  final _focus = List<FocusNode>.generate(6, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  String get _code => _digits.map((c) => c.text).join();
  bool get _full => _code.length == 6;

  Future<void> _logout() async {
    await ApiClient.instance.clearToken();
    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(
        DispatchModel(setUserAuthT, UserAuth(false, UserAccount.empty)));
    context.go('/login');
  }

  Future<void> _submit() async {
    if (!_full) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await AuthApi().verifyEmailRequest(_code);

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = "Invalid or expired code";
      });
      return;
    }

    // Optimistically flip isVerified so the router gate advances us onward
    // (to /setup if profile/consents are still pending, else the app) instead
    // of bouncing straight back here. The verify request already succeeded.
    final store = StoreProvider.of<AppState>(context);
    final user = store.state.userAuth.user;
    store.dispatch(DispatchModel(
        setUserAuthT, UserAuth(true, user.copyWith(isVerified: true))));

    setState(() => _busy = false);
    context.go('/messages');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    final state = StoreProvider.of<AppState>(context).state;
    final email = state.userAuth.user.email ?? '';

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: p.brandSoft),
                    child:
                        Icon(Icons.mark_email_read, color: p.brand, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Verify your email',
                    style: TextStyle(
                        color: p.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text('We sent a 6-digit code to ',
                          style: TextStyle(color: p.text2, fontSize: 14)),
                      Text(email,
                          style: TextStyle(
                              color: p.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        6,
                        (i) => Padding(
                            padding: EdgeInsets.only(right: i < 5 ? 9 : 0),
                            child: _digitBox(i))),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(_error!,
                          style: TextStyle(color: p.pink, fontSize: 13)),
                    ),
                  const SizedBox(height: 24),
                  CLBtn(
                    label: _busy ? 'Verifying…' : 'Verify',
                    onPressed: _busy || !_full ? null : _submit,
                    size: CLBtnSize.lg,
                    block: true,
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      Text("Wrong account? ",
                          style: TextStyle(color: p.text2, fontSize: 13.5)),
                      GestureDetector(
                        onTap: _logout,
                        child: Text('Logout',
                            style: TextStyle(
                                color: p.brand,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _digitBox(int i) {
    final p = cl(context);
    final filled = _digits[i].text.isNotEmpty;
    return SizedBox(
      width: 46,
      height: 56,
      child: TextField(
        controller: _digits[i],
        focusNode: _focus[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text),
        decoration: InputDecoration(
          filled: true,
          fillColor: p.input,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CLRadii.sm),
            borderSide:
                BorderSide(color: filled ? p.brand : p.border2, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CLRadii.sm),
            borderSide: BorderSide(color: p.brand, width: 1.5),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) {
          setState(() {});
          if (v.isNotEmpty && i < 5) _focus[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _focus[i - 1].requestFocus();
        },
      ),
    );
  }
}
