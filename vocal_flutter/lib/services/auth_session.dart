// AuthSession — Flutter port of iOS AuthSession.swift + GoogleSignIn.swift.
//
// Anonymous device-bound auth on first launch:
//  1. Mint a stable device UUID, persisted to SharedPreferences under
//     `vocal.device.id.v1`.
//  2. POST it to /api/auth/anonymous; get back {user_id, token, expires_at}.
//  3. Persist the snapshot in SharedPreferences under `vocal.auth.v1`.
//  4. Subsequent backend calls attach the bearer via `currentToken()`.
//
// Google upgrade flow:
//  - Use the `google_sign_in` package (handles Play Services + ID token cred).
//  - POST the id_token (+ optional link_anonymous_user_id + token) to
//    /api/auth/google. Update snapshot, provider → "google".
//
// Why SharedPreferences instead of Keychain (iOS) / KeyStore (Android):
//  - The iOS reference uses the Keychain (survives reinstall) for the device
//    ID so an anon user gets the SAME user_id back after wiping the app.
//    Android has no equivalent that's portable; SharedPreferences is wiped
//    on uninstall. Net result on Android: uninstall = fresh anon ID. That's
//    acceptable for now — the backend already keys merges by the prior
//    anon JWT, not by device ID. If we ship Auto Backup later (allowBackup
//    is the default), SharedPreferences gets backed up to Google Drive and
//    will restore on reinstall, which is the best we can do without
//    flutter_secure_storage.
//
// Concurrency: refresh() coalesces concurrent token-fetch calls so we never
// fire more than one /api/auth/anonymous request at a time. Mirrors the
// `pendingFetch` Task pattern in AuthSession.swift.
//
// Surface:
//   await session.bootstrap();           // call once from main()
//   session.userId / .provider / .displayName ...
//   final token = await session.currentToken();
//   await session.signInWithGoogle(linkAnonymousUserId: ..., linkAnonymousToken: ...);
//   await session.signOut(clearLocalData: true);

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'persistence.dart';
import 'voice_api.dart';
import 'widget_bridge.dart';

class AuthSession extends ChangeNotifier {
  // SharedPreferences keys.
  static const _snapshotKey = 'vocal.auth.v1';
  static const _deviceIdKey = 'vocal.device.id.v1';

  /// 60s clock-skew buffer — refresh if the token expires within this window.
  static const _refreshBuffer = Duration(seconds: 60);

  /// Network timeouts mirror iOS (anonymous: 10s, google: 15s).
  static const _anonTimeout = Duration(seconds: 10);
  static const _googleTimeout = Duration(seconds: 15);

  _Snapshot? _current;
  Future<_Snapshot>? _pendingRefresh;

  /// `google_sign_in` instance. Constructed lazily because the package
  /// initializes Play Services on first access on Android, and we don't
  /// want that to run on app-start for users who never sign in.
  GoogleSignIn? _google;

  // Public read-only state — kept as plain fields rather than `Stream` so
  // ChangeNotifier listeners can rebuild on `notifyListeners()`. Mirrors
  // the @Published properties on the iOS AuthSession.
  String? _userId;
  String _provider = '';
  String? _email;
  String? _displayName;
  String? _pictureUrl;
  bool _isAuthenticated = false;

  String? get userId => _userId;
  String get provider => _provider;
  String? get email => _email;
  String? get displayName => _displayName;
  String? get pictureUrl => _pictureUrl;
  bool get isAuthenticated => _isAuthenticated;

  /// Synchronous-cached access. Returns the token even if it's past expiry
  /// — callers wanting a fresh one should `await refreshIfNeeded()` first.
  /// Mirrors what iOS does as `current?.token` — used by code paths that
  /// can't await (e.g. setting up an http.Client in a build() method).
  String? get currentTokenSync => _current?.token;

  /// Returns a non-expired token, refreshing if needed. Use this in API
  /// call sites. Throws if a refresh is required and the network fails.
  Future<String?> currentToken() async {
    final snap = _current;
    if (snap != null &&
        snap.expiresAt.isAfter(DateTime.now().add(_refreshBuffer))) {
      return snap.token;
    }
    // Anonymous (or no snapshot at all): silently rotate via
    // /api/auth/anonymous — same device_id keeps the same user_id, so this
    // is safe and never surfaces auth prompts.
    if (snap == null || snap.provider == 'anonymous') {
      try {
        final fresh = await _refresh();
        return fresh.token;
      } catch (_) {
        // Network down — return whatever we had so the caller's HTTP layer
        // can still try (backend will 401, caller can show a toast).
        return snap?.token;
      }
    }
    // Google: per iOS comment, don't silently downgrade to anon. Return
    // the stale token; backend 401 → caller prompts the user to re-auth.
    // TODO(refresh): wire up google_sign_in.signInSilently() here to
    // re-mint a fresh google JWT without UI. Skipping for v1 — the 7-day
    // backend TTL makes this rare in practice.
    return snap.token;
  }

  /// Stamp a header map with `Authorization: Bearer <token>` if we have
  /// one. Never throws — a missing token leaves the headers untouched so
  /// the backend's body-fallback path can still resolve the user.
  Future<Map<String, String>> bearerHeaders([
    Map<String, String>? base,
  ]) async {
    final headers = <String, String>{...?base};
    final token = await currentToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Load persisted credentials and mint anonymous if absent. Called once
  /// from main() before runApp().
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw != null) {
      try {
        final snap = _Snapshot.decode(raw);
        _current = snap;
        _userId = snap.userId;
        _provider = snap.provider;
        _email = snap.email;
        _displayName = snap.displayName;
        _pictureUrl = snap.pictureUrl;
        // Mark as authenticated even if expired — currentToken() will
        // refresh lazily on the next backend call. Same posture as iOS.
        _isAuthenticated = true;
        notifyListeners();
        return;
      } catch (e) {
        // Corrupt snapshot — fall through to fresh anon mint. Don't throw;
        // a corrupted prefs file shouldn't brick app start.
        if (kDebugMode) {
          // ignore: avoid_print
          print('[AuthSession] snapshot decode failed: $e');
        }
      }
    }
    // No snapshot — mint anon. Failing this is non-fatal; subsequent
    // currentToken() calls will retry.
    try {
      await _refresh();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AuthSession] bootstrap anon mint failed: $e');
      }
    }
  }

  /// Trade a Google ID token for a backend JWT.
  ///
  /// [linkAnonymousUserId] + [linkAnonymousToken]: if the device is currently
  /// signed in anonymously, the caller can pass those so the backend can
  /// merge the anon account's meals/profile into the new Google identity.
  /// Defaults to the current snapshot's values when it's an anon session
  /// — callers normally don't need to pass these explicitly.
  ///
  /// Throws [AuthCancelledException] if the user backs out of the Google
  /// account picker; everything else is wrapped in [AuthException].
  Future<void> signInWithGoogle({
    String? linkAnonymousUserId,
    String? linkAnonymousToken,
  }) async {
    // Capture prior anon creds before any awaits to avoid a race with a
    // concurrent refresh that could swap _current out from under us.
    final prior = _current;
    final priorAnonUserId = linkAnonymousUserId ??
        (prior?.provider == 'anonymous' ? prior?.userId : null);
    final priorAnonToken = linkAnonymousToken ??
        (prior?.provider == 'anonymous' ? prior?.token : null);

    final idToken = await _fetchGoogleIdToken();
    final resp = await _exchangeGoogleIdToken(
      idToken: idToken,
      linkAnonymousUserId: priorAnonUserId,
      linkAnonymousToken: priorAnonToken,
    );

    final snap = _Snapshot(
      userId: resp['user_id'] as String,
      token: resp['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (resp['expires_at'] as num).toInt()),
      deviceId: prior?.deviceId ?? await _loadOrCreateDeviceId(),
      provider: 'google',
      email: resp['email'] as String?,
      displayName: resp['name'] as String?,
      pictureUrl: resp['picture'] as String?,
    );
    await _commitSnapshot(snap);
    // NOTE on local state: matches iOS — we do NOT clear the local meal
    // log on a Google upgrade. The user expects their anon-logged meals
    // to survive. Server-side merge handles cross-device continuity.
  }

  /// Capture an `X-Vocal-Anon-*` triplet from a response. The server emits
  /// these when an endpoint mints a fresh anon session for an unauthed
  /// caller (see `requireUserIdOrMint` server-side). Only persist when we
  /// don't already have a real Google/Apple session — never downgrade a
  /// signed-in identity to anon based on a response header.
  ///
  /// Best-effort: header parse failures, missing keys, or write errors
  /// are all silent. The caller is just plumbing API responses through
  /// here on their way to handling normal success/error.
  Future<void> captureMintedSessionIfNeeded(http.Response response) async {
    final prior = _current;
    if (prior != null && prior.provider != 'anonymous') return;
    // http.Response.headers downcases keys per RFC 7230 §3.2.
    final uid = response.headers['x-vocal-anon-user-id'];
    final tok = response.headers['x-vocal-anon-token'];
    final expStr = response.headers['x-vocal-anon-expires-at'];
    if (uid == null || tok == null || expStr == null) return;
    final expMs = int.tryParse(expStr);
    if (expMs == null) return;
    final deviceId = prior?.deviceId ?? await _loadOrCreateDeviceId();
    final snap = _Snapshot(
      userId: uid,
      token: tok,
      // Server emits milliseconds since epoch (matches /api/auth/anonymous).
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expMs),
      deviceId: deviceId,
      provider: 'anonymous',
    );
    _current = snap;
    _userId = uid;
    _provider = 'anonymous';
    _isAuthenticated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_snapshotKey, snap.encode());
    } catch (_) {}
    notifyListeners();
  }

  /// Erase the local session. Next request will mint a fresh anon user.
  ///
  /// [clearLocalData] — when true, also wipes the persisted meal log and
  /// the cached daily-macros snapshot. Use this from the Profile-screen
  /// "Sign out" button. The default false matches iOS so callers that
  /// just want to rotate a stale token don't accidentally nuke meals.
  Future<void> signOut({bool clearLocalData = false}) async {
    // Best-effort Google sign-out so the next signInWithGoogle() shows the
    // account chooser instead of silently re-using the prior account.
    try {
      await _google?.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotKey);
    _current = null;
    _userId = null;
    _provider = '';
    _email = null;
    _displayName = null;
    _pictureUrl = null;
    _isAuthenticated = false;
    if (clearLocalData) {
      await Persistence.clear();
      // Also drop the cached daily-macros snapshot + the widget snapshot
      // so app-intents and the home-screen widget don't keep showing the
      // previous user's totals until the next mutation.
      try {
        await prefs.remove('vocal.dailyMacrosSnapshot.v1');
      } catch (_) {}
      await WidgetBridge.clear();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Internals — anonymous refresh
  // ---------------------------------------------------------------------

  /// Force-refresh the anonymous session. Coalesces concurrent callers so
  /// the app never fires more than one /api/auth/anonymous request at a time.
  Future<_Snapshot> _refresh() {
    final existing = _pendingRefresh;
    if (existing != null) return existing;
    final fut = _doRefresh();
    _pendingRefresh = fut;
    return fut.whenComplete(() {
      _pendingRefresh = null;
    });
  }

  Future<_Snapshot> _doRefresh() async {
    // Reuse the same device_id across rotations so the user gets the same
    // anon user_id back if their token expired. The backend derives the
    // user_id deterministically from device_id.
    final deviceId = _current?.deviceId ?? await _loadOrCreateDeviceId();
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/anonymous');
    final http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'device_id': deviceId}),
          )
          .timeout(_anonTimeout);
    } on TimeoutException {
      throw AuthException('Anonymous auth timed out');
    } on SocketException catch (e) {
      throw AuthException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw AuthException('HTTP error: ${e.message}');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthException(
          'Anonymous auth failed: HTTP ${res.statusCode}');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw AuthException('Malformed anonymous response');
    }
    final snap = _Snapshot(
      userId: json['user_id'] as String,
      token: json['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['expires_at'] as num).toInt()),
      deviceId: deviceId,
      provider: 'anonymous',
    );
    await _commitSnapshot(snap);
    return snap;
  }

  // ---------------------------------------------------------------------
  // Internals — Google sign-in
  // ---------------------------------------------------------------------

  /// Returns the Google id_token. Throws [AuthCancelledException] if the
  /// user cancelled the account picker.
  Future<String> _fetchGoogleIdToken() async {
    // Lazily initialize. `serverClientId` is what makes google_sign_in
    // return an `idToken` — without it, you only get an `accessToken`
    // which the backend can't verify via tokeninfo.
    //
    // The serverClientId here MUST match a value in GOOGLE_CLIENT_ID_WEB
    // (or _ANDROID) on the backend so the audience check in
    // functions/api/auth/google.ts passes. We pull it from a
    // --dart-define so the same Dart code can target dev/staging/prod
    // without code edits.
    _google ??= GoogleSignIn(
      scopes: const ['email', 'profile', 'openid'],
      // serverClientId is the WEB client ID from the Google Cloud
      // Console project — Android sign-in is configured separately via
      // a SHA-1 fingerprint registered there (NO clientID literal goes
      // into Android source). On iOS we'd set `clientId` instead, but
      // iOS uses its own native flow (see GoogleSignIn.swift), so the
      // Flutter package's iOS path is unused.
      serverClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
        defaultValue: '',
      ),
    );
    final GoogleSignInAccount? account;
    try {
      account = await _google!.signIn();
    } catch (e) {
      // Distinguish a known cancel error code from real failures so the
      // caller can show "Sign in cancelled" vs an actual error toast.
      final msg = e.toString();
      if (msg.contains('canceled') || msg.contains('cancelled')) {
        throw AuthCancelledException();
      }
      throw AuthException('Google sign-in failed: $msg');
    }
    if (account == null) {
      // Older Android versions return null on cancel rather than throwing.
      throw AuthCancelledException();
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw AuthException(
          "Google didn't return an id_token — check that serverClientId is "
          'set (--dart-define=GOOGLE_SERVER_CLIENT_ID=...).');
    }
    return idToken;
  }

  Future<Map<String, dynamic>> _exchangeGoogleIdToken({
    required String idToken,
    required String? linkAnonymousUserId,
    required String? linkAnonymousToken,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/google');
    final payload = <String, dynamic>{'id_token': idToken};
    // Send the anon link fields even though backend may not yet handle
    // them — they're additive and the matching iOS commit (`f543bf1`)
    // ships the same shape. When the backend's merge endpoint lands we
    // won't need a Flutter rev.
    if (linkAnonymousUserId != null) {
      payload['link_anonymous_user_id'] = linkAnonymousUserId;
    }
    if (linkAnonymousToken != null) {
      payload['link_anonymous_token'] = linkAnonymousToken;
    }
    final http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_googleTimeout);
    } on TimeoutException {
      throw AuthException('Google token exchange timed out');
    } on SocketException catch (e) {
      throw AuthException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw AuthException('HTTP error: ${e.message}');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // Surface the server-side error message when present, so config
      // bugs ("Untrusted audience") aren't hidden behind a generic
      // status code.
      String? serverMsg;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && decoded['error'] is String) {
          serverMsg = decoded['error'] as String;
        }
      } catch (_) {}
      throw AuthException(
          serverMsg ?? 'Google auth failed: HTTP ${res.statusCode}');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw AuthException('Malformed Google auth response');
      }
      return decoded;
    } catch (e) {
      throw AuthException('Malformed Google auth response');
    }
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  Future<void> _commitSnapshot(_Snapshot snap) async {
    _current = snap;
    _userId = snap.userId;
    _provider = snap.provider;
    _email = snap.email;
    _displayName = snap.displayName;
    _pictureUrl = snap.pictureUrl;
    _isAuthenticated = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, snap.encode());
    notifyListeners();
  }

  Future<String> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    // dart:io / dart:math both have stronger options, but a UUID v4 via
    // a simple PRNG is fine for a stable device tag (no security
    // properties required — the value's only purpose is to keep the
    // same anon user_id across token rotations).
    final fresh = _uuidV4();
    await prefs.setString(_deviceIdKey, fresh);
    return fresh;
  }

  static String _uuidV4() {
    // Avoid pulling the `uuid` package for one call. RFC 4122 §4.4 random
    // variant; entropy via dart:math's Random.secure() (CSPRNG-backed
    // on all supported platforms).
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-'
        '${h.substring(20)}';
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

/// User cancelled the Google account picker. Callers should treat this as
/// a no-op (no error toast), matching iOS GoogleSignIn.Error.userCancelled.
class AuthCancelledException extends AuthException {
  AuthCancelledException() : super('Sign-in cancelled');
}

// ---------------------------------------------------------------------
// Snapshot codec
// ---------------------------------------------------------------------

class _Snapshot {
  final String userId;
  final String token;
  final DateTime expiresAt;
  final String deviceId;
  final String provider; // "anonymous" | "google" | "apple" | ""
  final String? email;
  final String? displayName;
  final String? pictureUrl;

  _Snapshot({
    required this.userId,
    required this.token,
    required this.expiresAt,
    required this.deviceId,
    required this.provider,
    this.email,
    this.displayName,
    this.pictureUrl,
  });

  String encode() => jsonEncode({
        'user_id': userId,
        'token': token,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'device_id': deviceId,
        'provider': provider,
        if (email != null) 'email': email,
        if (displayName != null) 'display_name': displayName,
        if (pictureUrl != null) 'picture_url': pictureUrl,
      });

  static _Snapshot decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return _Snapshot(
      userId: j['user_id'] as String,
      token: j['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (j['expires_at'] as num).toInt()),
      deviceId: j['device_id'] as String,
      provider: (j['provider'] as String?) ?? 'anonymous',
      email: j['email'] as String?,
      displayName: j['display_name'] as String?,
      pictureUrl: j['picture_url'] as String?,
    );
  }
}
