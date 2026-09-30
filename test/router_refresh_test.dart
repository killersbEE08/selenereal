import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Req {}

/// Regression for the blank "Analyzing your palm" / "Draw 3 cards" screens: a refreshListenable
/// tick (fired when the backend updated the user doc) rebuilt pushed routes with `extra == null`,
/// and `s.extra! as X` threw inside the page builder -> blank screen in release.
void main() {
  testWidgets('pushed extra route survives a router refresh', (t) async {
    final gate = ValueNotifier(0);
    _Req? last;
    final router = GoRouter(
      initialLocation: '/palm',
      refreshListenable: gate,
      routes: [
        GoRoute(path: '/palm', builder: (_, _) => const Text('PALM')),
        GoRoute(
          path: '/palm/analyze',
          redirect: (_, s) => (s.extra is _Req || last != null) ? null : '/palm',
          builder: (_, s) => Text('ANALYZE ${(last = (s.extra as _Req?) ?? last!).hashCode}'),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    final req = _Req();
    router.push('/palm/analyze', extra: req);
    await t.pumpAndSettle();
    expect(find.text('ANALYZE ${req.hashCode}'), findsOneWidget);

    gate.value++; // what a user-doc update used to trigger
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('ANALYZE ${req.hashCode}'), findsOneWidget);
  });
}
