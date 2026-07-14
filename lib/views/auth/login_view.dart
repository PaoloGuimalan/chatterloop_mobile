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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = "Please complete the field.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    LoginResponse? loginResponse =
        await AuthApi().loginRequest(_email.text.trim(), _password.text);

    if (!mounted) return;

    if (loginResponse?.authtoken == null || loginResponse?.usertoken == null) {
      setState(() {
        _busy = false;
        _error = "Login failed. Check your credentials and try again.";
      });
      return;
    }

    await ApiClient.instance.writeToken(loginResponse!.authtoken);
    Map<String, dynamic>? userResponse =
        JwtCodec.decode(loginResponse.usertoken);

    if (!mounted) return;
    StoreProvider.of<AppState>(context).dispatch(DispatchModel(
        setUserAuthT,
        UserAuth(
            true,
            UserAccount.fromDjangoJwt(userResponse ?? const {},
                allowedModules: loginResponse.allowedModules,
                activeEntity: loginResponse.activeEntity,
                personalEntityId: loginResponse.personalEntityId))));

    setState(() => _busy = false);
    if (mounted) context.go('/messages');
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
              constraints: const BoxConstraints(maxWidth: 380),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/chatterloop.png',
                          width: 38, height: 38),
                      const SizedBox(width: 10),
                      Text(
                        'Chatterloop',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Welcome back',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Log in to jump back into your loop.',
                    style: TextStyle(color: p.text2, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  CLField(
                    icon: Icons.alternate_email,
                    label: 'Email or Username',
                    placeholder: 'you@chatterloop.app',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 13),
                  CLField(
                    icon: Icons.lock_outline,
                    label: 'Password',
                    placeholder: '••••••••',
                    obscure: true,
                    controller: _password,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: TextStyle(color: p.pink, fontSize: 13)),
                    ),
                  const SizedBox(height: 4),
                  CLBtn(
                    label: _busy ? 'Logging in…' : 'Log In',
                    onPressed: _busy ? null : _submit,
                    size: CLBtnSize.lg,
                    block: true,
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Wrap(
                      children: [
                        Text("Don't have an account yet? ",
                            style: TextStyle(color: p.text2, fontSize: 13.5)),
                        GestureDetector(
                          onTap: () => context.push('/signup'),
                          child: Text('Sign Up',
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
}
