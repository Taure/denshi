-module(denshi_intent).

-export([value/1, combine/1]).

-spec value(atom()) -> non_neg_integer().
value(guilds) -> 1 bsl 0;
value(guild_members) -> 1 bsl 1;
value(guild_moderation) -> 1 bsl 2;
value(guild_expressions) -> 1 bsl 3;
value(guild_integrations) -> 1 bsl 4;
value(guild_webhooks) -> 1 bsl 5;
value(guild_invites) -> 1 bsl 6;
value(guild_voice_states) -> 1 bsl 7;
value(guild_presences) -> 1 bsl 8;
value(guild_messages) -> 1 bsl 9;
value(guild_message_reactions) -> 1 bsl 10;
value(guild_message_typing) -> 1 bsl 11;
value(direct_messages) -> 1 bsl 12;
value(direct_message_reactions) -> 1 bsl 13;
value(direct_message_typing) -> 1 bsl 14;
value(message_content) -> 1 bsl 15;
value(guild_scheduled_events) -> 1 bsl 16;
value(auto_moderation_configuration) -> 1 bsl 20;
value(auto_moderation_execution) -> 1 bsl 21;
value(guild_message_polls) -> 1 bsl 24;
value(direct_message_polls) -> 1 bsl 25.

-spec combine([atom()] | non_neg_integer()) -> non_neg_integer().
combine(Intents) when is_list(Intents) ->
    lists:foldl(fun(Intent, Acc) -> Acc bor value(Intent) end, 0, Intents);
combine(Bitmask) when is_integer(Bitmask) ->
    Bitmask.
