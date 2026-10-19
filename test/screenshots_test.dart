// Renders the app's screens to PNG files in docs/screenshots/.
//
//   flutter test test/screenshots_test.dart --dart-define=SCREENSHOTS=true
//
// Uses demo data, the real repository + sync engine (against an in-memory
// server), and real fonts (Segoe UI from Windows, CupertinoIcons).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:offline_tasks/data/local_store.dart';
import 'package:offline_tasks/data/task_repository.dart';
import 'package:offline_tasks/main.dart';
import 'package:offline_tasks/models/task.dart';
import 'package:offline_tasks/services/auth_service.dart';
import 'package:offline_tasks/services/notification_service.dart';
import 'package:offline_tasks/sync/connectivity_service.dart';
import 'package:offline_tasks/sync/sync_engine.dart';
import 'package:offline_tasks/ui/settings_screen.dart';
import 'package:offline_tasks/ui/sync_activity_screen.dart';
import 'package:offline_tasks/ui/task_editor_screen.dart';
import 'package:offline_tasks/ui/task_filter.dart';

import 'fakes.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');
const _out = 'docs/screenshots';

class FakeConnectivity extends ConnectivityService {
  FakeConnectivity(super.store);
  @override
  bool get hasNetwork => true;
  @override
  bool get isOnline => !forcedOffline;
}

class FakeAuth extends ChangeNotifier implements AuthService {
  @override
  String? get uid => 'demo-user';
  @override
  bool get isAnonymous => false;
  @override
  String? get email => 'pragdeesh@example.com';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  const win = 'C:/Windows/Fonts';
  final ui = ['$win/segoeui.ttf', '$win/seguisb.ttf', '$win/segoeuib.ttf'];
  for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto', '.SF Pro Text', '.SF Pro Display']) {
    await load(family, ui.where((f) => File(f).existsSync()).toList());
  }
  final pubCache = '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev';
  final icons = Directory(pubCache)
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.contains('cupertino_icons-'))
      .map((d) => '${d.path}/assets/CupertinoIcons.ttf')
      .last;
  await load('packages/cupertino_icons/CupertinoIcons', [icons]);
}

/// Fake iOS status bar so the shots read as a phone screen.
class _StatusBar extends StatelessWidget {
  const _StatusBar();
  @override
  Widget build(BuildContext context) {
    final c = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 18, 30, 0),
        child: Row(
          children: [
            Text('9:41',
                style: TextStyle(
                    fontFamily: 'CupertinoSystemText',
                    fontSize: 17, fontWeight: FontWeight.w600, color: c,
                    decoration: TextDecoration.none)),
            const Spacer(),
            Icon(CupertinoIcons.chart_bar_fill, size: 16, color: c),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.wifi, size: 16, color: c),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.battery_full, size: 24, color: c),
          ],
        ),
      ),
    );
  }
}

void main() {
  late Directory dir;
  late InMemoryRemote remote;
  late AppServices services;
  final boundary = GlobalKey();

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
  });

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      await _loadFonts();
      dir = await Directory.systemTemp.createTemp('shots');
      Hive.init(dir.path);
      remote = InMemoryRemote();
      final store = await LocalStore.open();
      final repo = TaskRepository(store);
      final conn = FakeConnectivity(store);
      final auth = FakeAuth();
      final sync = SyncEngine(
        repo: repo,
        store: store,
        remote: remote,
        isOnline: () => conn.isOnline,
        currentUid: () => auth.uid,
      );
      services = AppServices(
        store: store,
        repo: repo,
        connectivity: conn,
        auth: auth,
        sync: sync,
        notifications: NotificationService(),
        filter: TaskFilter(store),
      );

      final now = DateTime.now();
      DateTime at(int days, int h, [int m = 0]) =>
          DateTime(now.year, now.month, now.day + days, h, m);
      Future<Task> add(String title,
              {String notes = '',
              Priority p = Priority.medium,
              DateTime? due,
              String? cat,
              List<String> tags = const [],
              Recurrence r = Recurrence.none}) =>
          repo.create(
              title: title,
              description: notes,
              priority: p,
              dueAt: due,
              category: cat,
              tags: tags,
              recurrence: r);

      final report = await add('Submit GDG Wildcard entry',
          notes: 'APK, README, demo video', p: Priority.high,
          due: at(0, 21), cat: 'GDG', tags: ['deadline']);
      await add('Record demo video',
          notes: 'Show offline edits and the sync log',
          p: Priority.high, due: at(1, 18), cat: 'GDG', tags: ['video']);
      final milk = await add('Buy groceries',
          notes: 'Milk, eggs, bread', due: at(0, 19, 30), cat: 'Home', tags: ['errand']);
      await add('Water the plants', p: Priority.low, due: at(1, 8), cat: 'Home',
          r: Recurrence.daily);
      final gym = await add('Gym: leg day', p: Priority.low, cat: 'Health');
      final dsa = await add('Revise DSA: graphs', due: at(-1, 22), cat: 'Study',
          tags: ['exam']);
      await sync.syncNow();

      // A conflict: the server copy changes while this device edits offline.
      await sync.simulateRemoteEdit(milk);
      await repo.update(repo.recordOf(milk.id)!.task.copyWith(description: 'Milk, eggs, bread, coffee'));
      await sync.syncNow();
      await repo.setCompleted(repo.recordOf(gym.id)!.task, true);
      await sync.syncNow();
      await repo.setCompleted(repo.recordOf(report.id)!.task, false);
      await sync.syncNow();

      // A couple of changes still waiting (one failing) for the badges.
      remote.offline = true;
      await repo.update(repo.recordOf(dsa.id)!.task.copyWith(priority: Priority.high));
      await sync.syncNow();
      remote.offline = false;
      await sync.syncNow(force: true); // the retry succeeds
      await add('Call the bank', p: Priority.medium, due: at(2, 11));
    });
  }

  Future<void> pumpApp(WidgetTester tester, {Brightness b = Brightness.light}) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 162, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 162, bottom: 102);
    tester.platformDispatcher.platformBrightnessTestValue = b;
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          OfflineTasksApp(services: services),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CupertinoTheme(
              data: CupertinoThemeData(brightness: b),
              child: Builder(builder: (c) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(platformBrightness: b),
                    child: const _StatusBar(),
                  )),
            ),
          ),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> push(WidgetTester tester, Widget screen) async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(CupertinoPageRoute(builder: (_) => screen));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('screenshots', (tester) async {
    await seed(tester);

    await pumpApp(tester);
    await shot(tester, '01_tasks');

    await push(tester, TaskEditorScreen(task: services.repo.tasks
        .firstWhere((t) => t.title.startsWith('Buy groceries'))));
    await shot(tester, '02_task_details');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump(const Duration(seconds: 1));

    await push(tester, const SyncActivityScreen());
    await shot(tester, '03_sync_activity');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump(const Duration(seconds: 1));

    await push(tester, const SettingsScreen());
    await shot(tester, '04_settings');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump(const Duration(seconds: 1));

    await tester.runAsync(() => services.connectivity.setForcedOffline(true));
    await tester.pump();
    await shot(tester, '05_offline');

    await tester.longPress(find.textContaining('Call the bank'));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '06_task_actions');
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(seconds: 1));

    await tester.runAsync(() => services.connectivity.setForcedOffline(false));
    await pumpApp(tester, b: Brightness.dark);
    await shot(tester, '07_tasks_dark');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
  }, skip: !_enabled);
}
