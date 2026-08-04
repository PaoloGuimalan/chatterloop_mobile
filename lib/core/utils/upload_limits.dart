// The one upload size cap, for every surface that attaches a file.
//
// One constant because the number has to match the SERVER's - the multipart
// parsers on /posts/upload and /users/sendFiles both reject anything larger
// (server/reusables/vars/uploads.js). A client check that's more permissive
// than the server's just means the user waits for the whole upload before
// being told no; three separate copies of it here means they eventually
// disagree with each other too.
//
// Surfaces using it: the post composer, diary attachments, message
// attachments.
//
// Supplied at BUILD time rather than runtime - Dart has no process env on a
// phone, so this comes through `--dart-define-from-file=env.json` (see
// env.example.json) or `--dart-define=MAX_UPLOAD_FILE_SIZE_MB=...`, the same
// route SECRET_KEY takes. That means changing it needs a new build, unlike the
// server's, which is why the two are allowed to differ: as long as the app's
// cap is the smaller of the two, an older build just rejects a file the server
// would have accepted, rather than uploading one it will refuse.

/// Megabytes, straight from the define. Absent -> 0, which is why the value
/// below is guarded rather than used directly.
const int _definedMaxUploadMb =
    int.fromEnvironment('MAX_UPLOAD_FILE_SIZE_MB', defaultValue: 0);

/// The hardcoded fallback: what applies with no define, and the safety net for
/// a nonsensical one. A define of 0 or a negative number would otherwise be a
/// cap that rejects every file, and there is no runtime check to catch it -
/// `int.fromEnvironment` only substitutes its default when the key is entirely
/// absent, and a non-integer value fails the build outright.
const int _kDefaultMaxUploadMb = 100;

/// Effective cap in megabytes.
const int kMaxUploadMb =
    _definedMaxUploadMb > 0 ? _definedMaxUploadMb : _kDefaultMaxUploadMb;

const int kMaxUploadBytes = kMaxUploadMb * 1024 * 1024;

/// For user-facing copy - "Up to 100MB per file", "over 100MB".
const String kMaxUploadLabel = "${kMaxUploadMb}MB";
