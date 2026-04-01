-module(denshi_intent_test).
-include_lib("eunit/include/eunit.hrl").

value_test() ->
    ?assertEqual(1, denshi_intent:value(guilds)),
    ?assertEqual(1 bsl 9, denshi_intent:value(guild_messages)),
    ?assertEqual(1 bsl 15, denshi_intent:value(message_content)).

combine_list_test() ->
    Result = denshi_intent:combine([guilds, guild_messages, message_content]),
    ?assertEqual(1 bor (1 bsl 9) bor (1 bsl 15), Result).

combine_integer_passthrough_test() ->
    ?assertEqual(513, denshi_intent:combine(513)).

combine_empty_test() ->
    ?assertEqual(0, denshi_intent:combine([])).

combine_single_test() ->
    ?assertEqual(1, denshi_intent:combine([guilds])).
