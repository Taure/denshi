-module(denshi_codec_test).
-include_lib("eunit/include/eunit.hrl").

encode_map_test() ->
    Result = denshi_codec:encode(#{~"hello" => ~"world"}),
    ?assertEqual(#{~"hello" => ~"world"}, denshi_codec:decode(Result)).

encode_number_test() ->
    Result = denshi_codec:encode(#{~"op" => 1, ~"d" => null}),
    Decoded = denshi_codec:decode(Result),
    ?assertEqual(1, maps:get(~"op", Decoded)).

gateway_frame_test() ->
    Frame = denshi_codec:gateway_frame(1, null),
    Decoded = denshi_codec:decode(Frame),
    ?assertEqual(1, maps:get(~"op", Decoded)),
    ?assertEqual(null, maps:get(~"d", Decoded)).

gateway_frame_with_sequence_test() ->
    Frame = denshi_codec:gateway_frame(0, #{~"test" => true}, 42),
    Decoded = denshi_codec:decode(Frame),
    ?assertEqual(0, maps:get(~"op", Decoded)),
    ?assertEqual(42, maps:get(~"s", Decoded)).

gateway_frame_undefined_sequence_test() ->
    Frame = denshi_codec:gateway_frame(1, null, undefined),
    Decoded = denshi_codec:decode(Frame),
    ?assertNot(maps:is_key(~"s", Decoded)).

roundtrip_test() ->
    Original = #{~"key" => ~"value", ~"nested" => #{~"a" => 1}},
    ?assertEqual(Original, denshi_codec:decode(denshi_codec:encode(Original))).

decode_list_returns_maps_test() ->
    ?assertEqual(
        {ok, [#{~"id" => ~"1"}, #{~"id" => ~"2"}]},
        denshi_codec:decode_list(~"[{\"id\":\"1\"},{\"id\":\"2\"}]")
    ).

decode_list_empty_array_test() ->
    ?assertEqual({ok, []}, denshi_codec:decode_list(~"[]")).

decode_list_rejects_object_test() ->
    ?assertEqual({error, not_a_list}, denshi_codec:decode_list(~"{\"id\":\"1\"}")).

decode_list_rejects_non_maps_test() ->
    ?assertEqual(
        {error, not_a_list_of_objects}, denshi_codec:decode_list(~"[{\"id\":\"1\"},null,42]")
    ).

decode_list_raises_on_malformed_json_test() ->
    ?assertError(_, denshi_codec:decode_list(~"{not json")).
