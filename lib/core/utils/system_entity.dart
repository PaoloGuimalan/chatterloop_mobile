// The System bot, as every client and service agrees on it.
//
// A FIXED ID, NOT A LOOKUP
// ------------------------
// The same arrangement the moderator has: one constant, so every service
// agrees who "the platform" is without a config value that drifts between
// environments. The row is written by a migration (user_service, bot/
// migrations/0004_system_bot.py), so it exists everywhere the schema does.
//
// WHY A CLIENT HAS TO KNOW IT AT ALL
// ----------------------------------
// System answers built-in commands - /members, /created, /help - in
// conversations it is NOT a member of. It cannot be added to one, searched
// for, or removed. That is deliberate, and it is exactly why its name cannot
// be resolved the usual way: every other sender is named by finding them in
// the participant list, and System is never in it.
//
// Without this, its messages render as "Member 0002" in a group and, worse,
// as the OTHER PERSON'S NAME in a direct conversation - where the resolver
// reasonably assumes any sender who is not you must be them.
const String systemBotEntityId = "00000000-0000-4000-8000-000000000002";

/// The name to show for a message System sent.
const String systemBotDisplayName = "System";

bool isSystemBot(String? entityId) =>
    entityId != null && entityId == systemBotEntityId;
