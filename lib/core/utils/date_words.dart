// Mirrors webapp's reusable.ts formattedDateToWords/ordinal_suffix_of - used
// for the profile page's "Joined" and "Born in" lines.

String ordinalSuffix(int i) {
  final j = i % 10;
  final k = i % 100;
  if (j == 1 && k != 11) return "${i}st";
  if (j == 2 && k != 12) return "${i}nd";
  if (j == 3 && k != 13) return "${i}rd";
  return "${i}th";
}

const _monthNames = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/// Formats a server "MM/DD/YYYY" date string (e.g. dateCreated.date) into
/// "5th of March 2024", matching formattedDateToWords's default branch.
String? formattedDateToWords(String? mmddyyyy) {
  if (mmddyyyy == null || mmddyyyy.isEmpty) return null;
  final parts = mmddyyyy.split("/");
  if (parts.length != 3) return null;
  final month = int.tryParse(parts[0]);
  final day = int.tryParse(parts[1]);
  final year = parts[2];
  if (month == null || day == null || month < 1 || month > 12) return null;
  return "${ordinalSuffix(day)} of ${_monthNames[month - 1]} $year";
}

/// Formats a birthdate already split into {month name, day, year} (the
/// server sends the month pre-named, unlike dateCreated above) into
/// "5th of March 1995", matching Profile.tsx's inline birthdate formatting.
String? formattedBirthdate(String? month, String? day, String? year) {
  if (month == null || month.isEmpty || day == null || day.isEmpty) {
    return null;
  }
  final dayNum = int.tryParse(day);
  if (dayNum == null) return null;
  return "${ordinalSuffix(dayNum)} of $month ${year ?? ''}".trim();
}

/// Presence timestamps arrive in two different shapes depending on source:
/// the /u/activecontacts snapshot sends Mongo's raw `lastSeen` (ISO8601,
/// parses directly), while live "active_users" SSE events send
/// server/reusables/hooks/getDate.js's dateGetter() output instead -
/// "YYYY-MM-DD HH:MM:SS.mmm +ZZZZ" (Django-style, space-separated, no
/// colon in the offset) - not itself valid ISO8601. Tries the fast path
/// first, falls back to reshaping the Django format into one DateTime.parse
/// accepts.
DateTime? parseServerTimestamp(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;
  final match = RegExp(
          r'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}(?:\.\d+)?) ([+-]\d{2})(\d{2})$')
      .firstMatch(raw);
  if (match == null) return null;
  return DateTime.tryParse(
      "${match.group(1)}T${match.group(2)}${match.group(3)}:${match.group(4)}");
}

const _monthAbbreviations = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

/// The "X ago" ladder shared by timeSince/timeSinceShort - null once past
/// falls outside the under-a-week window, so each caller supplies its own
/// absolute-date fallback format.
String? _relativeTimeSince(DateTime past) {
  final seconds = DateTime.now().difference(past).inSeconds;
  if (seconds < 5) return "just now";
  if (seconds < 60) {
    return "$seconds second${seconds == 1 ? '' : 's'} ago";
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return "$minutes minute${minutes == 1 ? '' : 's'} ago";
  }
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return "$hours hour${hours == 1 ? '' : 's'} ago";
  }
  final days = hours ~/ 24;
  if (days < 7) {
    return "$days day${days == 1 ? '' : 's'} ago";
  }
  return null;
}

/// Mirrors webapp's reusable.ts timeSince() - a relative "X ago" label for
/// anything under a week old, else a prose absolute date.
String timeSince(DateTime past) =>
    _relativeTimeSince(past) ??
    "${ordinalSuffix(past.day)} of ${_monthNames[past.month - 1]} ${past.year}";

/// Same relative-time ladder as timeSince, but the >7-days fallback matches
/// webapp's Messages.tsx conversation-list format ("Jul 8, 2026") instead of
/// timeSince's prose "8th of July 2026" - used for the messages list row.
String timeSinceShort(DateTime past) =>
    _relativeTimeSince(past) ??
    "${_monthAbbreviations[past.month - 1]} ${past.day}, ${past.year}";
