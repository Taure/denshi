-module(denshi_rest_test).
-include_lib("eunit/include/eunit.hrl").

get_channel_messages_rejects_zero_limit_test() ->
    ?assertError(
        function_clause,
        denshi_rest:get_channel_messages(~"123", 0, ~"token")
    ).

get_channel_messages_rejects_limit_above_hundred_test() ->
    ?assertError(
        function_clause,
        denshi_rest:get_channel_messages(~"123", 101, ~"token")
    ).

exports_message_reads_test() ->
    Exports = denshi_rest:module_info(exports),
    ?assert(lists:member({get_channel_messages, 3}, Exports)),
    ?assert(lists:member({get_message, 3}, Exports)).

path_traversal_in_message_id_rejected_test() ->
    ?assertError(
        {invalid_snowflake, _},
        denshi_rest:get_message(~"123", ~"1/../../../../guilds/999/members/555", ~"token")
    ).

path_traversal_in_channel_id_rejected_test() ->
    ?assertError(
        {invalid_snowflake, _},
        denshi_rest:get_message(~"1/../../guilds/999", ~"456", ~"token")
    ).

query_injection_in_channel_id_rejected_test() ->
    ?assertError(
        {invalid_snowflake, _},
        denshi_rest:get_channel_messages(~"123/messages?limit=100&x=", 1, ~"token")
    ).

oversized_channel_id_rejected_test() ->
    ?assertError(
        {invalid_snowflake, _},
        denshi_rest:get_channel(binary:copy(~"1", 21), ~"token")
    ).

empty_channel_id_rejected_test() ->
    ?assertError({invalid_snowflake, _}, denshi_rest:get_channel(<<>>, ~"token")).

interaction_token_charset_enforced_test() ->
    ?assertError(
        {invalid_url_token, _},
        denshi_rest:create_interaction_response(~"1", ~"tok/../../evil", #{}, ~"token")
    ).
