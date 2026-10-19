import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Account handling. The app never blocks on sign-in: tasks are stored
/// locally from the first launch, and an anonymous account is created the
/// first time the device is online. Registering upgrades that same anonymous
/// account (same uid, so nothing has to move); signing in to an existing
/// account on a second device gives multi-device sync.
class AuthService extends ChangeNotifier {
  AuthService(this._auth) {
    _sub = _auth.userChanges().listen((_) => notifyListeners());
  }

  final FirebaseAuth _auth;
  late final StreamSubscription<User?> _sub;
  bool _signingIn = false;

  User? get user => _auth.currentUser;
  String? get uid => user?.uid;
  bool get isAnonymous => user?.isAnonymous ?? true;
  String? get email => user?.email;

  /// Creates an anonymous account if there is none. Safe to call often.
  Future<void> ensureSignedIn() async {
    if (user != null || _signingIn) return;
    _signingIn = true;
    try {
      await _auth.signInAnonymously().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    } finally {
      _signingIn = false;
    }
  }

  /// Turns the current (anonymous) account into an email account, keeping
  /// its uid and therefore all of its synced tasks.
  Future<void> register(String email, String password) async {
    final cred = EmailAuthProvider.credential(email: email, password: password);
    final current = user;
    if (current != null && current.isAnonymous) {
      await current.linkWithCredential(cred);
    } else {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    notifyListeners();
  }

  Future<void> signOut() => _auth.signOut();

  static String describe(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Wrong email or password.',
        'email-already-in-use' || 'credential-already-in-use' =>
          'That email already has an account. Sign in instead.',
        'weak-password' => 'Use a password of at least 6 characters.',
        'invalid-email' => 'That email address is not valid.',
        'network-request-failed' => 'No connection. Signing in needs the internet.',
        'operation-not-allowed' =>
          'This sign-in method is not enabled in the Firebase project.',
        _ => e.message ?? e.code,
      };
    }
    return '$e';
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
