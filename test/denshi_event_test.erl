-module(denshi_event_test).
-include_lib("eunit/include/eunit.hrl").
-include("denshi.hrl").

name_known_events_test() ->
    ?assertEqual(ready, denshi_event:name(~"READY")),
    ?assertEqual(message_create, denshi_event:name(~"MESSAGE_CREATE")),
    ?assertEqual(interaction_create, denshi_event:name(~"INTERACTION_CREATE")),
    ?assertEqual(guild_create, denshi_event:name(~"GUILD_CREATE")),
    ?assertEqual(guild_member_add, denshi_event:name(~"GUILD_MEMBER_ADD")),
    ?assertEqual(channel_create, denshi_event:name(~"CHANNEL_CREATE")),
    ?assertEqual(presence_update, denshi_event:name(~"PRESENCE_UPDATE")),
    ?assertEqual(voice_state_update, denshi_event:name(~"VOICE_STATE_UPDATE")).

name_unknown_event_test() ->
    ?assertEqual(unknown, denshi_event:name(~"TOTALLY_UNKNOWN_EVENT_XYZ_123")).

parse_dispatch_test() ->
    Payload = #{
        ~"op" => 0,
        ~"t" => ~"MESSAGE_CREATE",
        ~"d" => #{~"content" => ~"hello"},
        ~"s" => 5
    },
    Event = denshi_event:parse(Payload),
    ?assertEqual(0, Event#denshi_event.op),
    ?assertEqual(message_create, Event#denshi_event.name),
    ?assertEqual(#{~"content" => ~"hello"}, Event#denshi_event.data),
    ?assertEqual(5, Event#denshi_event.sequence).

parse_hello_test() ->
    Payload = #{
        ~"op" => 10,
        ~"d" => #{~"heartbeat_interval" => 41250}
    },
    Event = denshi_event:parse(Payload),
    ?assertEqual(10, Event#denshi_event.op),
    ?assertEqual(undefined, Event#denshi_event.name),
    ?assertEqual(undefined, Event#denshi_event.sequence).

parse_heartbeat_ack_test() ->
    Payload = #{~"op" => 11, ~"d" => null, ~"t" => null, ~"s" => null},
    Event = denshi_event:parse(Payload),
    ?assertEqual(11, Event#denshi_event.op),
    ?assertEqual(undefined, Event#denshi_event.name).
