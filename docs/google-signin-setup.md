# Google Sign-In setup — iOS + Android Flutter

Both platforms post a Google ID token to `POST /api/auth/google` and get back
a VoCal JWT. The backend verifies tokens via Google's `tokeninfo` endpoint
and checks the audience against the configured client IDs.

## Step 1 — Google Cloud Console

1. https://console.cloud.google.com → APIs & Services → OAuth consent screen.
   Configure as **External** with scopes `openid`, `email`, `profile`.
   Add `vocal.best` as an authorized domain.
2. APIs & Services → Credentials → **Create Credentials → OAuth client ID**.
   Create THREE clients:

   **iOS**
   - Application type: iOS
   - Bundle ID: `com.EricSpencer.VoCal`
   - Copy the client ID — looks like `1234-abc.apps.googleusercontent.com`

   **Android**
   - Application type: Android
   - Package name: `best.vocal.vocal`
   - SHA-1 cert fingerprint: run `./gradlew signingReport` from
     `vocal_flutter/android/` and copy the `SHA1` line.

   **Web** (used by `google_sign_in` Flutter as `serverClientId`)
   - Application type: Web application
   - Copy this client ID.

## Step 2 — Cloudflare Pages secrets

```
GOOGLE_CLIENT_ID_IOS     = 1234-ios.apps.googleusercontent.com
GOOGLE_CLIENT_ID_ANDROID = 1234-android.apps.googleusercontent.com
GOOGLE_CLIENT_ID_WEB     = 1234-web.apps.googleusercontent.com
JWT_SECRET               = <32+ random bytes>
```

Without these the backend accepts any valid Google token (audience check
skipped). Set them before production traffic.

## Step 3 — iOS

Paste the iOS client ID into [VoCal/VoCal/GoogleSignIn.swift](../VoCal/VoCal/GoogleSignIn.swift):

```swift
static let iosClientID = "1234-ios.apps.googleusercontent.com"
```

In Xcode: target VoCal → **Info** tab → **URL Types** → **+**. URL Schemes
field: paste the **reversed** client ID, e.g. `com.googleusercontent.apps.1234-ios`.

That's the only project edit — no SDK to install. The Google button on
the onboarding pitch screen calls `AuthSession.shared.signInWithGoogle()`
which kicks off `ASWebAuthenticationSession`.

## Step 4 — Flutter (vocal_flutter branch)

Add to `vocal_flutter/pubspec.yaml`:

```yaml
dependencies:
  google_sign_in: ^6.2.1
```

Create `vocal_flutter/lib/services/auth_session.dart`:

```dart
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  static const String _webClientId = '1234-web.apps.googleusercontent.com';
  static const String _apiBase = 'https://vocal.best/api';

  final _google = GoogleSignIn(
    serverClientId: _webClientId,
    scopes: const ['email', 'profile', 'openid'],
  );

  String? _token;
  String? _userId;
  String? _email;
  String? _displayName;

  String? get token => _token;
  String? get userId => _userId;
  String? get email => _email;
  String? get displayName => _displayName;
  bool get isAuthenticated => _token != null;

  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth.token');
    _userId = prefs.getString('auth.userId');
    _email = prefs.getString('auth.email');
    _displayName = prefs.getString('auth.displayName');
  }

  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw Exception('Sign-in cancelled');
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('No id_token returned');

    final res = await http.post(
      Uri.parse('$_apiBase/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Backend rejected token: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _token = data['token'] as String;
    _userId = data['user_id'] as String;
    _email = data['email'] as String?;
    _displayName = data['name'] as String?;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth.token', _token!);
    await prefs.setString('auth.userId', _userId!);
    if (_email != null) await prefs.setString('auth.email', _email!);
    if (_displayName != null) await prefs.setString('auth.displayName', _displayName!);
  }

  Future<void> signOut() async {
    await _google.signOut();
    _token = null;
    _userId = null;
    _email = null;
    _displayName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth.token');
    await prefs.remove('auth.userId');
    await prefs.remove('auth.email');
    await prefs.remove('auth.displayName');
  }

  Map<String, String> get authHeaders =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};
}
```

Then in `main.dart`:

```dart
final auth = AuthSession();
await auth.loadFromCache();
runApp(MultiProvider(providers: [
  ChangeNotifierProvider.value(value: appModel),
  Provider<AuthSession>.value(value: auth),
], child: const VoCalApp()));
```

Add the Google button to the onboarding pitch step:

```dart
ElevatedButton.icon(
  onPressed: () async {
    try { await context.read<AuthSession>().signInWithGoogle(); }
    catch (e) { /* show error */ }
  },
  icon: const Icon(Icons.account_circle, color: Colors.black),
  label: const Text('Sign in with Google'),
  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF6F4EC)),
)
```

Wire `auth.authHeaders` into every `http.post` to `/api/voice/parse`,
`/api/coach`, `/api/photo/parse`, `/api/barcode/:code`.

## Step 5 — Verify

Endpoint is live at `https://vocal.best/api/auth/google`. Smoke test:

```bash
# Empty body → 400:
curl -s -X POST https://vocal.best/api/auth/google \
  -H 'Content-Type: application/json' -d '{}'
# → {"error":"id_token required"}

# Bogus token → 401 with Google's rejection reason:
curl -s -X POST https://vocal.best/api/auth/google \
  -H 'Content-Type: application/json' -d '{"id_token":"fake"}'
# → {"error":"Google rejected the id_token: ..."}
```
