// Global response hook — single place every API client funnels its
// `http.Response` through so AuthSession can extract the
// X-Vocal-Anon-* triplet the server emits when it auto-mints an anon
// session for an unauthed caller.
//
// Why a global static (instead of a closure per client): the alternative
// is plumbing AuthSession through every *ApiAuth singleton, and that's
// what the existing `*ApiAuth.tokenLoader` indirection already does for
// outbound auth headers — but tokenLoader is async (it can refresh on
// the way out), whereas this hook is sync inspection on the way back.
// Two closures per client gets noisy fast. One central hook keeps the
// surface tiny.

import 'package:http/http.dart' as http;

class ApiResponseHook {
  /// Wired by main() to AuthSession.captureMintedSessionIfNeeded. Every
  /// API client calls notify() after a successful response (HTTP 2xx) so
  /// any X-Vocal-Anon-* headers get persisted before the response body
  /// is parsed.
  ///
  /// Best-effort: never throws. A null listener means nothing's wired up
  /// (e.g. tests) and the call is a no-op.
  static void Function(http.Response)? listener;

  static void notify(http.Response response) {
    final l = listener;
    if (l == null) return;
    try {
      l(response);
    } catch (_) {
      // Swallowed — capture failure shouldn't break the API call's own
      // success path.
    }
  }
}
