-module(denshi_interaction_test).
-include_lib("eunit/include/eunit.hrl").
-include("denshi.hrl").

parse_test() ->
    Data = #{
        ~"id" => ~"12345",
        ~"application_id" => ~"app1",
        ~"type" => 2,
        ~"data" => #{~"name" => ~"test"},
        ~"guild_id" => ~"guild1",
        ~"channel_id" => ~"chan1",
        ~"member" => #{~"user" => #{~"id" => ~"user1"}},
        ~"token" => ~"interaction_token",
        ~"version" => 1
    },
    I = denshi_interaction:parse(Data),
    ?assertEqual(~"12345", I#denshi_interaction.id),
    ?assertEqual(~"app1", I#denshi_interaction.application_id),
    ?assertEqual(2, I#denshi_interaction.type),
    ?assertEqual(~"test", maps:get(~"name", I#denshi_interaction.data)),
    ?assertEqual(~"guild1", I#denshi_interaction.guild_id),
    ?assertEqual(~"chan1", I#denshi_interaction.channel_id),
    ?assertEqual(~"interaction_token", I#denshi_interaction.token).

parse_minimal_test() ->
    Data = #{
        ~"id" => ~"12345",
        ~"application_id" => ~"app1",
        ~"type" => 1,
        ~"token" => ~"tok",
        ~"version" => 1
    },
    I = denshi_interaction:parse(Data),
    ?assertEqual(undefined, I#denshi_interaction.guild_id),
    ?assertEqual(undefined, I#denshi_interaction.data).

pong_test() ->
    ?assertEqual(#{~"type" => 1}, denshi_interaction:pong()).

message_test() ->
    Result = denshi_interaction:message(#{~"content" => ~"hello"}),
    ?assertEqual(#{~"type" => 4, ~"data" => #{~"content" => ~"hello"}}, Result).

deferred_message_test() ->
    ?assertEqual(#{~"type" => 5}, denshi_interaction:deferred_message()).

deferred_message_with_data_test() ->
    Data = #{~"flags" => 64},
    ?assertEqual(#{~"type" => 5, ~"data" => Data}, denshi_interaction:deferred_message(Data)).

update_message_test() ->
    Data = #{~"content" => ~"updated"},
    ?assertEqual(#{~"type" => 7, ~"data" => Data}, denshi_interaction:update_message(Data)).

modal_test() ->
    ModalData = #{~"title" => ~"My Modal", ~"components" => []},
    Result = denshi_interaction:modal(~"my_modal", ModalData),
    ?assertEqual(9, maps:get(~"type", Result)),
    ResultData = maps:get(~"data", Result),
    ?assertEqual(~"my_modal", maps:get(~"custom_id", ResultData)),
    ?assertEqual(~"My Modal", maps:get(~"title", ResultData)).
