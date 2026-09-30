import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../core/astro.dart';
import '../core/birth_fields.dart';
import '../core/theme.dart';
import '../core/validators.dart';
import '../core/widgets.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/palm_store.dart';

class PalmRequest {
  PalmRequest(this.photo, this.hand, {this.subject});

  /// Compressed JPEG bytes (EXIF stripped).
  final Uint8List photo;
  final String hand;

  /// Set when reading someone else's palm (null = the signed-in user's own palm).
  final PalmSubject? subject;
}

/// Details of the person whose palm is read when it isn't the user's own.
class PalmSubject {
  const PalmSubject({required this.name, required this.relation, this.dob, this.birthTime, this.birthPlace});
  final String name, relation;
  final String? dob, birthTime, birthPlace;

  Map<String, dynamic> toJson() => {'name': name, 'relation': relation, 'dob': ?dob, 'birthTime': ?birthTime, if (birthPlace != null && birthPlace!.isNotEmpty) 'birthPlace': birthPlace};
}

/// Relation ids accepted by the server (functions/src/prompts/palm.ts RELATIONS).
const palmRelations = [('partner', 'Partner'), ('crush', 'Crush'), ('friend', 'Friend'), ('family', 'Family'), ('other', 'Other')];

/// Set before the camera opens. If Android kills the app while the camera is in front, the
/// relaunch goes back to the palm tab (see AuthGate.takeResumeRoute) and the photo is recovered.
const resumeRouteKey = 'resumeRoute';
const _palmDraftKey = 'palmDraft';

final palmReadingDocProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, id) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance.doc('users/$uid/palmReadings/$id').snapshots().map((s) => s.data());
});

/// Local palm photo bytes for a reading (null when not on this device / browser session).
final palmPhotoProvider = FutureProvider.family<Uint8List?, String>((ref, id) => PalmStore.load(id));

class PalmHomeScreen extends ConsumerStatefulWidget {
  const PalmHomeScreen({super.key});
  @override
  ConsumerState<PalmHomeScreen> createState() => _PalmHomeState();
}

class _PalmHomeState extends ConsumerState<PalmHomeScreen> {
  String _hand = 'left';
  Uint8List? _photo;
  bool _picking = false;

  // "Someone else's palm"
  bool _forOther = false;
  final _otherName = TextEditingController();
  final _otherPlace = TextEditingController();
  String _relation = 'partner';
  DateTime? _otherDob;
  TimeOfDay? _otherTime;
  bool _otherTimeUnknown = true;

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    // Android may destroy the activity while the camera app is open; the photo is then delivered
    // on the next launch through retrieveLostData instead of pickImage's future.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostPhoto());
  }

  @override
  void dispose() {
    _otherName.dispose();
    _otherPlace.dispose();
    super.dispose();
  }

  Future<void> _recoverLostPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.isEmpty || !mounted) return;
      final x = lost.file ?? lost.files?.firstOrNull;
      if (x != null) {
        setState(() => _picking = true);
        await _usePicked(x);
      }
    } catch (_) {
      // Nothing to recover.
    } finally {
      ref.read(prefsProvider).remove(resumeRouteKey);
      if (mounted) setState(() => _picking = false);
    }
  }

  void _saveDraft() {
    ref
        .read(prefsProvider)
        .setString(
          _palmDraftKey,
          jsonEncode({
            'hand': _hand,
            'forOther': _forOther,
            'name': _otherName.text,
            'relation': _relation,
            'dob': _otherDob?.toIso8601String(),
            'time': _otherTime == null ? null : formatBirthTime(_otherTime!),
            'timeUnknown': _otherTimeUnknown,
            'place': _otherPlace.text,
          }),
        );
  }

  void _restoreDraft() {
    final raw = ref.read(prefsProvider).getString(_palmDraftKey);
    if (raw == null) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      _hand = d['hand'] == 'right' ? 'right' : 'left';
      _forOther = d['forOther'] == true;
      _otherName.text = '${d['name'] ?? ''}';
      _relation = palmRelations.any((r) => r.$1 == d['relation']) ? d['relation'] as String : 'partner';
      _otherDob = DateTime.tryParse('${d['dob']}');
      _otherTime = parseBirthTime(d['time'] as String?);
      _otherTimeUnknown = d['timeUnknown'] != false;
      _otherPlace.text = '${d['place'] ?? ''}';
    } catch (_) {
      // Ignore a corrupt draft.
    }
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _picking = true);
    final prefs = ref.read(prefsProvider);
    _saveDraft();
    if (source == ImageSource.camera) await prefs.setString(resumeRouteKey, '/palm');
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 95, requestFullMetadata: false);
      if (x == null) return;
      await _usePicked(x);
    } catch (e) {
      final denied = e is PlatformException && (e.code == 'camera_access_denied' || e.code == 'photo_access_denied');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(denied ? 'Please allow camera access in Settings to take a palm photo.' : 'Could not open the camera. Please try again or choose from your gallery.')));
      }
    } finally {
      await prefs.remove(resumeRouteKey);
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Compress to ≤1600px JPEG q85 and strip EXIF (location etc.). Rotation is baked into the pixels,
  /// so Gemini and the line overlay see exactly the same image. On web the browser canvas
  /// re-encodes the image, which also drops EXIF.
  Future<void> _usePicked(XFile x) async {
    try {
      final raw = await x.readAsBytes();
      Uint8List out;
      try {
        out = await FlutterImageCompress.compressWithList(raw, minWidth: 1600, minHeight: 1600, quality: 85, keepExif: false, format: CompressFormat.jpeg);
      } catch (_) {
        out = raw; // the server validates JPEG/PNG by magic bytes
      }
      if (out.isEmpty) out = raw;
      if (out.length > 5 * 1024 * 1024) throw Exception('Photo is too large');
      if (mounted) setState(() => _photo = out);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not use that photo. Please try another one.')));
    }
  }

  PalmSubject? _subject() {
    if (!_forOther) return null;
    final place = _otherPlace.text.trim();
    return PalmSubject(
      name: _otherName.text.trim(),
      relation: _relation,
      dob: _otherDob == null ? null : DateFormat('yyyy-MM-dd').format(_otherDob!),
      birthTime: _otherTimeUnknown || _otherTime == null ? null : formatBirthTime(_otherTime!),
      birthPlace: place.isEmpty ? null : place,
    );
  }

  void _analyze() {
    final user = ref.read(userDocProvider).value;
    if (_forOther) {
      final err = Validators.name(_otherName.text) ?? Validators.place(_otherPlace.text, required: false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.replaceFirst('your name', 'their name'))));
        return;
      }
    }
    if (user != null && !user.premium && user.lifetimePalm >= freePalmLifetime && !useEmulator) {
      context.push('/paywall');
      return;
    }
    ref.read(prefsProvider).remove(_palmDraftKey);
    context.push('/palm/analyze', extra: PalmRequest(_photo!, _hand, subject: _subject()));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        HeroHeader(
          title: 'AI Palm Reading',
          subtitle: 'Discover what your hands reveal',
          image: 'assets/images/hero_palm.webp',
          headingLead: 'Your Destiny in Your',
          headingAccent: 'Hands',
          description: 'Get an AI-powered palm reading with detailed insights about your personality, love, career and future.',
          action: OutlinePillButton(label: 'My Readings', icon: Ic.book, onPressed: () => context.push('/readings?type=palm')),
          height: 400,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(child: _Trust(Ic.sparkles, 'AI Analysis', 'Detailed insights')),
              Expanded(child: _Trust(Ic.flash, 'Instant Results', 'In seconds')),
              Expanded(child: _Trust(Ic.shield, 'Private & Secure', 'Your data stays safe')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.cta),
                      child: const Center(child: AppIcon(Ic.camera, color: AppColors.onGold)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Take a Photo of Your Palm',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          Text('Good lighting and a clear, open palm give the best results.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    OutlinePillButton(label: 'Tips', icon: Ic.bulb, onPressed: () => _showTips(context)),
                  ],
                ),
                const SizedBox(height: 14),
                if (_photo != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(_photo!, height: 220, width: double.infinity, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: CircleIconButton(icon: Ic.close, tooltip: 'Remove photo', onTap: () => setState(() => _photo = null)),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _SourceButton(icon: Ic.camera, title: 'Take Photo', sub: 'Use your camera', selected: true, onTap: _picking ? null : () => _pick(ImageSource.camera)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SourceButton(icon: Ic.pic, title: 'Choose from Gallery', sub: 'Upload a clear image', onTap: _picking ? null : () => _pick(ImageSource.gallery)),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select Hand',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                    TextButton(onPressed: () => _showWhichHand(context), child: const Text('Which hand?')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _HandButton(title: 'Left Hand', sub: 'Inner self, personality', selected: _hand == 'left', flip: true, onTap: () => setState(() => _hand = 'left')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HandButton(title: 'Right Hand', sub: 'Career, future, actions', selected: _hand == 'right', onTap: () => setState(() => _hand = 'right')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: GlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Whose palm is it?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _WhoButton(icon: Ic.user, title: 'My palm', selected: !_forOther, onTap: () => setState(() => _forOther = false)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WhoButton(icon: Ic.group, title: "Someone else's", selected: _forOther, onTap: () => setState(() => _forOther = true)),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: _forOther ? _otherForm() : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          child: GradientButton(
            label: _photo == null
                ? 'Add a palm photo first'
                : (_forOther ? 'Analyze ${_otherName.text.trim().isEmpty ? 'Their' : "${_otherName.text.trim().split(' ').first}'s"} Palm' : 'Analyze My Palm'),
            onPressed: _photo == null ? null : _analyze,
          ),
        ),
        const SectionTitle('What You’ll Discover'),
        SizedBox(
          height: 170,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: const [
              _Discover(Ic.heart, 'Love & Relationships', 'Your love life, emotional nature and compatibility.'),
              _Discover(Ic.briefcase, 'Career & Success', 'Career strengths, opportunities and prospects.'),
              _Discover(Ic.lotus, 'Personality Analysis', 'Your unique traits, strengths and hidden talents.'),
              _Discover(Ic.compass, 'Life Path & Future', 'Guidance about your journey and upcoming phases.'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          child: GlowCard(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                Image.asset('assets/images/palm_celestial.webp', width: 140, height: 140, fit: BoxFit.cover, excludeFromSemantics: true),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(Ic.search, color: Colors.white, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Detailed Line Analysis',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text('Our AI analyzes the life, heart, head and fate lines, plus your hand shape and mounts.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const DisclaimerText(),
      ],
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(t.toUpperCase(), style: AppType.overline(color: AppColors.textSecondary)),
  );

  Widget _otherForm() {
    final sign = _otherDob == null ? null : sunSignFor(_otherDob!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Text('Tell us a little about them so the reading feels personal.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        _label('Their name'),
        TextFormField(
          key: const Key('otherNameField'),
          controller: _otherName,
          textCapitalization: TextCapitalization.words,
          autocorrect: false,
          inputFormatters: Validators.nameFormatters,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'e.g. Riya'),
        ),
        _label('They are my'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final r in palmRelations) PillChip(label: r.$2, selected: _relation == r.$1, dense: true, onTap: () => setState(() => _relation = r.$1))],
        ),
        _label('Date of birth (optional)'),
        GlowCard(
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _otherDob ?? DateTime(2000, 1, 1), firstDate: DateTime(1920), lastDate: DateTime.now());
            if (d != null) setState(() => _otherDob = d);
          },
          child: Row(
            children: [
              const IconBadge(Ic.cake, color: AppColors.gold, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _otherDob == null ? 'Select their birthday' : DateFormat.yMMMMd().format(_otherDob!),
                  style: AppType.ui(size: 15, weight: FontWeight.w500, color: _otherDob == null ? AppColors.textMuted : AppColors.text),
                ),
              ),
              if (sign != null)
                Text(
                  sign.name,
                  style: AppType.ui(size: 14, weight: FontWeight.w700, color: AppColors.gold),
                ),
            ],
          ),
        ),
        _label('Time of birth (optional)'),
        BirthTimeField(time: _otherTime, unknown: _otherTimeUnknown, onTime: (t) => setState(() => _otherTime = t), onUnknown: (v) => setState(() => _otherTimeUnknown = v)),
        _label('Place of birth (optional)'),
        BirthPlaceField(controller: _otherPlace, required: false),
      ],
    );
  }

  void _showTips(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const SingleChildScrollView(
      child: Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tips for a great reading',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          _Tip(Ic.sun, 'Use bright, even light — daylight near a window is perfect.'),
          _Tip(Ic.hand, 'Open your palm flat, fingers relaxed and slightly apart.'),
          _Tip(Ic.pic, 'Fill the frame with your whole palm and fingers.'),
          _Tip(Ic.camera, 'Hold steady to avoid blur; no filters.'),
          _Tip(Ic.eye, 'Remove gloves, heavy rings or anything covering the lines.'),
        ],
      ),
    ),
    ),
  );

  void _showWhichHand(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const SingleChildScrollView(
      child: Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which hand to choose?',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          _Tip(Ic.heart, 'Left hand: your inner self, natural talents and the personality you were born with.'),
          _Tip(Ic.briefcase, 'Right hand: your actions, career and how you’re using your potential right now.'),
          _Tip(Ic.bulb, 'Tip: many readers use your dominant hand for the present and future. Try both to compare!'),
        ],
      ),
    ),
    ),
  );
}

class _Tip extends StatelessWidget {
  const _Tip(this.e, this.t);
  final String e, t;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(e, color: AppColors.gold, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t,
              style: AppType.ui(size: 14, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Trust extends StatelessWidget {
  const _Trust(this.icon, this.title, this.sub);
  final String icon;
  final String title, sub;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
          color: AppColors.gold.withValues(alpha: 0.1),
        ),
        child: Center(child: AppIcon(icon, color: AppColors.gold, size: 17)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.icon, required this.title, required this.sub, this.onTap, this.selected = false});
  final String icon;
  final String title, sub;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => GlowCard(
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected ? AppColors.cta : null,
            color: selected ? null : const Color(0x14FFFFFF),
            border: selected ? null : Border.all(color: AppColors.border),
          ),
          child: Center(child: AppIcon(icon, color: selected ? AppColors.onGold : AppColors.text, size: 24)),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}

class _WhoButton extends StatelessWidget {
  const _WhoButton({required this.icon, required this.title, required this.selected, required this.onTap});
  final String icon, title;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.cta : null,
          color: selected ? null : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, color: selected ? AppColors.onGold : AppColors.text, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected ? AppColors.onGold : Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HandButton extends StatelessWidget {
  const _HandButton({required this.title, required this.sub, required this.selected, required this.onTap, this.flip = false});
  final String title, sub;
  final bool selected, flip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.cta : null,
          color: selected ? null : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Row(
          children: [
            Transform.flip(
              flipX: flip,
              child: AppIcon(Ic.handFill, color: selected ? AppColors.onGold : AppColors.text, size: 26),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Discover extends StatelessWidget {
  const _Discover(this.e, this.t, this.b);
  final String e, t, b;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: SizedBox(
      width: 150,
      child: GlowCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            IconBadge(e, color: AppColors.gold, size: 44, circle: true),
            const SizedBox(height: 6),
            Text(
              t,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                b,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------- Analyzing (flow screens 1 & 2) ----------------

class PalmAnalyzingScreen extends ConsumerStatefulWidget {
  const PalmAnalyzingScreen({super.key, required this.request});
  final PalmRequest request;
  @override
  ConsumerState<PalmAnalyzingScreen> createState() => _PalmAnalyzingState();
}

class _PalmAnalyzingState extends ConsumerState<PalmAnalyzingScreen> with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  Timer? _timer;
  double _progress = 0.02;
  int _step = 0;
  bool _working = false; // switches to the "AI Working" screen
  Map<String, dynamic>? _invalid;
  String? _error;
  late String _readingId;
  bool _completed = false;

  static const _steps = ['Detecting palm lines', 'Analyzing hand shape', 'Reading patterns and mounts', 'Generating insights'];
  static const _workSteps = ['Interpreting your palm lines', 'Analyzing hand shape & mounts', 'Matching patterns with ancient wisdom', 'Creating your personalized reading'];
  static const _facts = [
    'Your dominant hand shows your current path, while your non-dominant hand reveals your natural traits.',
    'Palmistry has been practiced for thousands of years in India, China and Greece.',
    'No two palms are alike — even identical twins have different palm lines.',
    'The four hand types are linked to the classical elements: Earth, Air, Fire and Water.',
  ];

  @override
  void initState() {
    super.initState();
    _readingId = FirebaseFirestore.instance.collection('_').doc().id;
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        // Eases toward 95% while waiting for the server.
        _progress = math.min(0.95, _progress + (0.95 - _progress) * 0.025);
        _step = math.min(_steps.length - 1, (_progress * 4.4).floor());
        if (_progress > 0.35) _working = true;
      });
    });
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _invalid = null;
      _progress = 0.02;
      _working = false;
    });
    try {
      await PalmStore.save(_readingId, widget.request.photo);
      await uploadPalm(_readingId, widget.request.photo);
      final res = await Api.analyzePalm(_readingId, widget.request.hand, subject: widget.request.subject?.toJson());
      if (!mounted) return;
      if (res['status'] == 'invalid') {
        await PalmStore.delete(_readingId).catchError((_) {});
        setState(() => _invalid = Map<String, dynamic>.from(res['validation'] as Map));
        return;
      }
      _completed = true;
      setState(() => _progress = 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) context.pushReplacement('/palm/result/$_readingId');
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.needsPremium) {
        context.pushReplacement('/paywall');
        return;
      }
      setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.');
    }
  }

  @override
  void dispose() {
    // Remove the local copy unless it belongs to a finished reading (used by the line overlay).
    if (!_completed) PalmStore.delete(_readingId).ignore();
    _timer?.cancel();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _invalid != null
        ? _invalidView()
        : _error != null
        ? MascotMessage(title: 'Reading interrupted', message: _error!, action: 'Try again', onAction: _run)
        : AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: _working ? _workingView() : _scanView());
    return Scaffold(
      body: CosmicBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleIconButton(icon: Ic.left, tooltip: 'Back', onTap: () => context.pop()),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'AI Palm Reading',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
              ),
              Expanded(
                child: Center(child: SingleChildScrollView(child: body)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanView() => Padding(
    key: const ValueKey('scan'),
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      children: [
        SizedBox(
          height: 300,
          width: 250,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(widget.request.photo, fit: BoxFit.cover),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.glow, width: 2.5),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _scan,
                builder: (_, _) => Positioned(
                  left: 0,
                  right: 0,
                  top: 10 + _scan.value * 270,
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.glow,
                      boxShadow: [BoxShadow(color: AppColors.glow, blurRadius: 16, spreadRadius: 2)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Analyzing your palm...', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'Our AI is studying the lines, shapes and patterns on your palm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _progressBar(),
        const SizedBox(height: 16),
        GlowCard(
          child: Column(
            children: [
              for (var i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const AppIcon(Ic.sparkles2, color: AppColors.glow, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_steps[i], style: TextStyle(color: i <= _step ? Colors.white : AppColors.textMuted)),
                      ),
                      if (i < _step)
                        const AppIcon(Ic.check, color: AppColors.success, size: 18)
                      else if (i == _step)
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.glow)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _progressBar() => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(height: 8, color: const Color(0x14FFFFFF)),
              FractionallySizedBox(
                widthFactor: _progress,
                child: Container(height: 8, decoration: const BoxDecoration(gradient: AppColors.cta)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('${(_progress * 100).round()}%', style: const TextStyle(color: Colors.white)),
    ],
  );

  Widget _workingView() {
    final active = ((_progress - 0.35) / 0.6 * _workSteps.length).floor().clamp(0, _workSteps.length - 1);
    return Padding(
      key: const ValueKey('work'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _scan,
            builder: (_, child) => Transform.translate(offset: Offset(0, -8 * _scan.value), child: child),
            child: Image.asset('assets/images/robot.webp', height: 250, excludeFromSemantics: true),
          ),
          const SizedBox(height: 8),
          Text('Reading the energy\nin your hands...', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _progressBar(),
          const SizedBox(height: 16),
          GlowCard(
            child: Column(
              children: [
                for (var i = 0; i < _workSteps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        AppIcon([Ic.hand, Ic.search, Ic.crystalBall, Ic.sparkles][i], size: 18, color: i <= active ? AppColors.gold : AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_workSteps[i], style: TextStyle(color: i <= active ? Colors.white : AppColors.textMuted)),
                        ),
                        if (i < active) const AppIcon(Ic.check, color: AppColors.success, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlowCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(Ic.bulb, color: AppColors.gold, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Did you know?',
                        style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(_facts[(_progress * 10).floor() % _facts.length], style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _invalidView() {
    final reason = '${_invalid!['reason']}';
    final tip = '${_invalid!['tip']}';
    final title = switch (reason) {
      'not_a_hand' => "We couldn't find a palm",
      'back_of_hand' => 'That looks like the back of your hand',
      'blurry' => 'The photo is a little blurry',
      'too_dark' => 'The photo is too dark',
      'too_far' => 'Your hand is too far away',
      'partial_hand' => 'Part of your palm is cut off',
      'multiple_hands' => 'Please show just one hand',
      _ => "Let's try another photo",
    };
    return MascotMessage(
      image: 'assets/images/wizard_cat.webp',
      title: title,
      message: tip.isEmpty ? 'Use bright light, open your palm flat and fill the frame.' : tip,
      action: 'Retake Photo',
      onAction: () => context.pop(),
    );
  }
}

/// Helper used by results screens to present a reading loaded from Firestore.
PalmReading? palmFromDoc(Map<String, dynamic>? d) => d?['result'] is Map ? PalmReading(Map<String, dynamic>.from(d!['result'] as Map)) : null;
