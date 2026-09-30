import 'package:flutter/material.dart';

import 'theme.dart';
import 'validators.dart';
import 'widgets.dart';

/// "HH:mm" (24h) as stored in Firestore <-> TimeOfDay.
String formatBirthTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
TimeOfDay? parseBirthTime(String? s) {
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(s ?? '');
  return m == null ? null : TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
}

/// Birth time picker tile with an "I don't know" option (a common case, so it never blocks sign-up).
class BirthTimeField extends StatelessWidget {
  const BirthTimeField({super.key, required this.time, required this.unknown, required this.onTime, required this.onUnknown});
  final TimeOfDay? time;
  final bool unknown;
  final ValueChanged<TimeOfDay> onTime;
  final ValueChanged<bool> onUnknown;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: unknown ? 0.5 : 1, // visibly disabled while "I don't know" is ticked
        child: GlowCard(
          onTap: unknown
              ? null
              : () async {
                  final t = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 12, minute: 0), helpText: 'Time of birth');
                  if (t != null) onTime(t);
                },
          child: Row(
            children: [
              const IconBadge(Ic.time, color: AppColors.gold, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  unknown ? 'Birth time unknown' : (time == null ? 'Select your birth time' : time!.format(context)),
                  style: AppType.ui(size: 15, weight: FontWeight.w500, color: time == null || unknown ? AppColors.textMuted : AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
      CheckboxListTile(
        value: unknown,
        onChanged: (v) => onUnknown(v ?? false),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text("I don't know the exact time", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ),
    ],
  );
}

/// City / country of birth.
class BirthPlaceField extends StatelessWidget {
  const BirthPlaceField({super.key, required this.controller, this.required = true, this.fieldKey});
  final TextEditingController controller;
  final bool required;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    textCapitalization: TextCapitalization.words,
    autocorrect: false,
    inputFormatters: Validators.placeFormatters,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (v) => Validators.place(v, required: required),
    decoration: const InputDecoration(
      hintText: 'e.g. Patna, India',
      helperText: 'City and country',
      prefixIcon: Padding(
        padding: EdgeInsets.all(12),
        child: AppIcon(Ic.location, size: 20, color: AppColors.gold),
      ),
    ),
  );
}
