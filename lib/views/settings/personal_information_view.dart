// Personal Information settings section - mobile counterpart of webapp's
// PersonalInformation.tsx. Name (first/middle/last), birthdate (month/day/
// year), gender. Save sends ONLY the changed fields (diff) to
// PUT /api/user/me, mirroring the webapp's fieldsToUpdate build exactly, and
// Reset restores the values the screen opened with. Alerts surface as
// SnackBars (the mobile equivalent of the webapp's toast alerts).

import 'package:chatterloop_app/core/design/tokens.dart';
import 'package:chatterloop_app/core/design/widgets.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:chatterloop_app/core/redux/types.dart';
import 'package:chatterloop_app/core/requests/profile_api.dart';
import 'package:chatterloop_app/models/redux_models/dispatch_model.dart';
import 'package:chatterloop_app/models/user_models/user_auth_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState
    extends State<PersonalInformationScreen> {
  late UserAccount _original;
  bool _initialized = false;
  bool _saving = false;

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  String? _month; // full month name
  String? _day;
  String? _year;
  String? _gender; // 'male' | 'female' | 'other'

  void _initFrom(UserAccount user) {
    if (_initialized) return;
    _original = user;
    _resetFields();
    _initialized = true;
  }

  void _resetFields() {
    _first.text = _original.firstname;
    _middle.text = _original.middlename == 'N/A' ? '' : _original.middlename;
    _last.text = _original.lastname;
    _month = _normalizeMonth(_original.birthdate?.month);
    _day = _emptyToNull(_original.birthdate?.day);
    _year = _emptyToNull(_original.birthdate?.year);
    _gender = _normalizeGender(_original.gender);
  }

  String? _emptyToNull(String? v) => (v == null || v.isEmpty) ? null : v;

  /// Birthdate month can arrive as a full name ("March") or a number ("3") -
  /// map either onto the dropdown's full-name values.
  String? _normalizeMonth(String? m) {
    if (m == null || m.isEmpty) return null;
    for (final name in _months) {
      if (name.toLowerCase() == m.toLowerCase()) return name;
    }
    final n = int.tryParse(m);
    if (n != null && n >= 1 && n <= 12) return _months[n - 1];
    return null;
  }

  String? _normalizeGender(String? g) {
    if (g == null || g.isEmpty) return null;
    final lower = g.toLowerCase();
    if (lower == 'male' || lower == 'female') return lower;
    if (lower.startsWith('other')) return 'other';
    return null;
  }

  int _daysInMonth(String? monthName, String? year) {
    final mi = monthName == null ? -1 : _months.indexOf(monthName);
    final y = int.tryParse(year ?? '') ?? 2000;
    if (mi < 0) return 31;
    return DateTime(y, mi + 2, 0).day; // day 0 of next month = last of this
  }

  /// Same datetime shape the webapp's getFormattedDate produces, or null when
  /// month/day/year aren't all set.
  String? _formatted(String? monthName, String? day, String? year) {
    if (monthName == null || day == null || year == null) return null;
    final mi = _months.indexOf(monthName);
    if (mi < 0) return null;
    final mm = (mi + 1).toString().padLeft(2, '0');
    final dd = day.padLeft(2, '0');
    return '$year-$mm-$dd 08:00:00.000 +0800';
  }

  bool _isOver13(String? formatted) {
    if (formatted == null) return false;
    final dt = DateTime.tryParse(formatted.split(' ').first);
    if (dt == null) return false;
    final now = DateTime.now();
    var age = now.year - dt.year;
    if (now.month < dt.month || (now.month == dt.month && now.day < dt.day)) {
      age--;
    }
    return age >= 13;
  }

  void _alert(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final firstName = _first.text.trim();
    final middleName = _middle.text.trim();
    final lastName = _last.text.trim();

    final fields = <String, dynamic>{};

    if (firstName.isEmpty) {
      _alert('First name cannot be empty');
      return;
    }
    if (firstName != _original.firstname) fields['first_name'] = firstName;

    if (middleName.isEmpty) {
      if (_original.middlename != 'N/A') fields['middle_name'] = 'N/A';
    } else if (middleName != _original.middlename) {
      fields['middle_name'] = middleName;
    }

    if (lastName.isEmpty) {
      _alert('Last name cannot be empty');
      return;
    }
    if (lastName != _original.lastname) fields['last_name'] = lastName;

    final currentBirthdate = _formatted(
        _normalizeMonth(_original.birthdate?.month),
        _emptyToNull(_original.birthdate?.day),
        _emptyToNull(_original.birthdate?.year));
    final newBirthdate = _formatted(_month, _day, _year);
    if (newBirthdate != null && newBirthdate != currentBirthdate) {
      if (!_isOver13(newBirthdate)) {
        _alert('Age must be 13 years or above');
        return;
      }
      fields['birthdate'] = newBirthdate;
    }

    if (_gender != null && _gender != _original.gender) {
      fields['gender'] = _gender;
    }

    if (fields.isEmpty) {
      _alert('There are no fields to be updated');
      return;
    }

    setState(() => _saving = true);
    final data = await ProfileApi().updateProfileRequest(fields);
    if (!mounted) return;
    if (data == null) {
      setState(() => _saving = false);
      _alert('Could not save changes. Please try again.');
      return;
    }

    final account = UserAccount.fromDjangoJwt(data,
        allowedModules: _original.allowedModules,
        activeEntity: _original.activeEntity,
        personalEntityId: _original.personalEntityId);
    StoreProvider.of<AppState>(context)
        .dispatch(DispatchModel(setUserAuthT, UserAuth(true, account)));
    setState(() {
      _saving = false;
      _original = account;
      _initialized = false;
    });
    _initFrom(account);
    _alert('Profile updated');
  }

  @override
  Widget build(BuildContext context) {
    final p = cl(context);
    return StoreConnector<AppState, AppState>(
      converter: (store) => store.state,
      builder: (context, state) {
        _initFrom(state.userAuth.user);
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(title: const Text('Personal Information')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(p, 'Name', 'Change your name how you prefer it.'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: CLField(
                          icon: Icons.person_outline,
                          label: 'First',
                          controller: _first)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: CLField(
                          label: 'Middle (optional)', controller: _middle)),
                ]),
                const SizedBox(height: 12),
                CLField(
                    icon: Icons.badge_outlined,
                    label: 'Last',
                    controller: _last),
                const SizedBox(height: 26),
                _sectionHeader(p, 'Birthdate', 'Update your birthdate.'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      flex: 13,
                      child: _dropdown(p, 'Month', _month, _months, (v) {
                        setState(() {
                          _month = v;
                          if (_day != null &&
                              (int.tryParse(_day!) ?? 0) >
                                  _daysInMonth(v, _year)) {
                            _day = null;
                          }
                        });
                      })),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 10,
                      child: _dropdown(
                          p,
                          'Day',
                          _day,
                          List.generate(
                              _daysInMonth(_month, _year), (i) => '${i + 1}'),
                          (v) => setState(() => _day = v))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 10,
                      child: _dropdown(
                          p,
                          'Year',
                          _year,
                          List.generate(
                              100, (i) => '${DateTime.now().year - i}'),
                          (v) => setState(() => _year = v))),
                ]),
                const SizedBox(height: 26),
                _sectionHeader(p, 'Gender', 'Update your gender.'),
                const SizedBox(height: 10),
                Row(children: [
                  _genderButton(p, 'Male', 'male'),
                  const SizedBox(width: 10),
                  _genderButton(p, 'Female', 'female'),
                  const SizedBox(width: 10),
                  _genderButton(p, 'Others', 'other'),
                ]),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CLBtn(
                      label: _saving ? 'Saving…' : 'Save',
                      onPressed: _saving ? null : _save,
                      size: CLBtnSize.md,
                    ),
                    const SizedBox(width: 8),
                    CLBtn(
                      label: 'Reset',
                      variant: CLBtnVariant.soft,
                      onPressed: _saving ? null : () => setState(_resetFields),
                      size: CLBtnSize.md,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionHeader(CLPalette p, String title, String desc) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 13, color: p.text2)),
        ],
      );

  Widget _genderButton(CLPalette p, String label, String value) {
    final active = _gender == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gender = value),
        borderRadius: BorderRadius.circular(CLRadii.sm),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? p.brand : p.surface,
            border:
                Border.all(color: active ? Colors.transparent : p.border2),
            borderRadius: BorderRadius.circular(CLRadii.sm),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : p.text2,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _dropdown(CLPalette p, String label, String? value,
      List<String> options, ValueChanged<String?> onChanged) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(CLRadii.sm),
        border: Border.all(color: p.border2),
      ),
      child: DropdownButton<String>(
        value: value,
        hint: Text(label, style: TextStyle(color: p.text3, fontSize: 14)),
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
}
