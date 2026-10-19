import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:provider/provider.dart';

import 'data/firestore_remote_store.dart';
import 'data/local_store.dart';
import 'data/task_repository.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'sync/connectivity_service.dart';
import 'sync/sync_engine.dart';
import 'ui/home_screen.dart';
import 'ui/task_filter.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

/// Everything the app needs, created once at startup.
class AppServices {
  AppServices({
    required this.store,
    required this.repo,
    required this.connectivity,
    required this.auth,
    required this.sync,
    required this.notifications,
    required this.filter,
  });

  final LocalStore store;
  final TaskRepository repo;
  final ConnectivityService connectivity;
  final AuthService auth;
  final SyncEngine sync;
  final NotificationService notifications;
  final TaskFilter filter;

  static Future<AppServices> create() async {
    await Hive.initFlutter();
    final store = await LocalStore.open();
    final repo = TaskRepository(store);

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Firestore's built-in offline cache is disabled on purpose: offline
    // storage and syncing are handled by this app (Hive + SyncEngine).
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

    final connectivity = ConnectivityService(store);
    final auth = AuthService(FirebaseAuth.instance);
    final sync = SyncEngine(
      repo: repo,
      store: store,
      remote: FirestoreRemoteStore(FirebaseFirestore.instance),
      isOnline: () => connectivity.isOnline,
      currentUid: () => auth.uid,
    );
    final notifications = NotificationService();
    final services = AppServices(
      store: store,
      repo: repo,
      connectivity: connectivity,
      auth: auth,
      sync: sync,
      notifications: notifications,
      filter: TaskFilter(store),
    );

    // Wiring.
    String? lastUid = auth.uid;
    auth.addListener(() {
      if (auth.uid != lastUid) {
        lastUid = auth.uid;
        sync.onConnectivityChanged();
      }
    });
    connectivity.addListener(() async {
      if (connectivity.isOnline) await auth.ensureSignedIn();
      sync.onConnectivityChanged();
    });
    repo.addTaskChangeListener(notifications.sync);

    await connectivity.start();
    // Not awaited: a flaky network must never delay opening the app.
    if (connectivity.isOnline) auth.ensureSignedIn();
    await sync.start();

    // Not awaited: reminders must never hold up the first frame.
    notifications.init().then((_) => notifications.syncAll(repo.tasks));
    return services;
  }
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppServices> _future = AppServices.create();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) return OfflineTasksApp(services: snap.data!);
        return CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.cupertino,
          localizationsDelegates: _localizations,
          home: CupertinoPageScaffold(
            child: Center(
              child: snap.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle,
                              size: 48, color: CupertinoColors.systemRed),
                          const SizedBox(height: 12),
                          const Text('Could Not Open Your Tasks',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('${snap.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          CupertinoButton.filled(
                            onPressed: () =>
                                setState(() => _future = AppServices.create()),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoActivityIndicator(radius: 14),
                        SizedBox(height: 14),
                        Text('Loading your tasks…'),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Cupertino widgets need only Cupertino strings; the Material ones cover the
/// few framework widgets (e.g. text selection) that look them up.
const _localizations = <LocalizationsDelegate<dynamic>>[
  DefaultMaterialLocalizations.delegate,
  DefaultCupertinoLocalizations.delegate,
  DefaultWidgetsLocalizations.delegate,
];

class OfflineTasksApp extends StatefulWidget {
  const OfflineTasksApp({super.key, required this.services});
  final AppServices services;

  @override
  State<OfflineTasksApp> createState() => _OfflineTasksAppState();
}

class _OfflineTasksAppState extends State<OfflineTasksApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.services.sync.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        Provider.value(value: s.store),
        Provider.value(value: s.notifications),
        ChangeNotifierProvider.value(value: s.repo),
        ChangeNotifierProvider.value(value: s.connectivity),
        ChangeNotifierProvider.value(value: s.auth),
        ChangeNotifierProvider.value(value: s.sync),
        ChangeNotifierProvider.value(value: s.filter),
      ],
      child: const CupertinoApp(
        title: 'Offline Tasks',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.cupertino,
        localizationsDelegates: _localizations,
        home: HomeScreen(),
      ),
    );
  }
}
