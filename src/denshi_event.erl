-module(denshi_event).

-export([name/1, parse/1]).

-include("denshi.hrl").

-spec name(binary()) -> atom().
name(~"READY") ->
    ready;
name(~"RESUMED") ->
    resumed;
name(~"GUILD_CREATE") ->
    guild_create;
name(~"GUILD_UPDATE") ->
    guild_update;
name(~"GUILD_DELETE") ->
    guild_delete;
name(~"GUILD_MEMBER_ADD") ->
    guild_member_add;
name(~"GUILD_MEMBER_UPDATE") ->
    guild_member_update;
name(~"GUILD_MEMBER_REMOVE") ->
    guild_member_remove;
name(~"CHANNEL_CREATE") ->
    channel_create;
name(~"CHANNEL_UPDATE") ->
    channel_update;
name(~"CHANNEL_DELETE") ->
    channel_delete;
name(~"MESSAGE_CREATE") ->
    message_create;
name(~"MESSAGE_UPDATE") ->
    message_update;
name(~"MESSAGE_DELETE") ->
    message_delete;
name(~"MESSAGE_REACTION_ADD") ->
    message_reaction_add;
name(~"MESSAGE_REACTION_REMOVE") ->
    message_reaction_remove;
name(~"INTERACTION_CREATE") ->
    interaction_create;
name(~"PRESENCE_UPDATE") ->
    presence_update;
name(~"TYPING_START") ->
    typing_start;
name(~"USER_UPDATE") ->
    user_update;
name(~"VOICE_STATE_UPDATE") ->
    voice_state_update;
name(~"VOICE_SERVER_UPDATE") ->
    voice_server_update;
name(~"GUILD_ROLE_CREATE") ->
    guild_role_create;
name(~"GUILD_ROLE_UPDATE") ->
    guild_role_update;
name(~"GUILD_ROLE_DELETE") ->
    guild_role_delete;
name(~"GUILD_BAN_ADD") ->
    guild_ban_add;
name(~"GUILD_BAN_REMOVE") ->
    guild_ban_remove;
name(~"INVITE_CREATE") ->
    invite_create;
name(~"INVITE_DELETE") ->
    invite_delete;
name(~"THREAD_CREATE") ->
    thread_create;
name(~"THREAD_UPDATE") ->
    thread_update;
name(~"THREAD_DELETE") ->
    thread_delete;
name(Other) when is_binary(Other) ->
    try
        binary_to_existing_atom(string:lowercase(Other))
    catch
        error:badarg ->
            logger:warning(~"Unknown Discord event: ~ts", [Other]),
            unknown
    end.

-spec parse(map()) -> #denshi_event{}.
parse(#{~"op" := Op} = Payload) ->
    #denshi_event{
        op = Op,
        name =
            case maps:get(~"t", Payload, null) of
                null -> undefined;
                T -> name(T)
            end,
        data = maps:get(~"d", Payload, undefined),
        sequence =
            case maps:get(~"s", Payload, null) of
                null -> undefined;
                S -> S
            end
    }.
