-module(denshi_rest).

-export([
    get_gateway_bot/1,
    send_message/3,
    create_interaction_response/4,
    edit_original_response/4,
    create_global_command/3,
    create_guild_command/4,
    get_channel/2,
    get_guild/2,
    get_channel_messages/3,
    get_message/3,
    delete_message/3
]).

-define(MAX_MESSAGE_LIMIT, 100).
-define(DEFAULT_RETRY_AFTER_MS, 1000).
-define(MAX_SNOWFLAKE_LEN, 20).
-define(MAX_URL_TOKEN_LEN, 256).

-spec get_gateway_bot(binary()) -> {ok, map()} | {error, term()}.
get_gateway_bot(Token) ->
    do_get(~"/gateway/bot", Token).

-spec send_message(binary(), map(), binary()) -> {ok, map()} | {error, term()}.
send_message(ChannelId, Message, Token) ->
    Path = iolist_to_binary([~"/channels/", snowflake(ChannelId), ~"/messages"]),
    do_post(Path, Message, Token).

-spec create_interaction_response(binary(), binary(), map(), binary()) ->
    {ok, map() | binary()} | {error, term()}.
create_interaction_response(InteractionId, InteractionToken, Response, Token) ->
    Path = iolist_to_binary([
        ~"/interactions/", snowflake(InteractionId), ~"/", url_token(InteractionToken), ~"/callback"
    ]),
    do_post(Path, Response, Token).

-spec edit_original_response(binary(), binary(), map(), binary()) ->
    {ok, map()} | {error, term()}.
edit_original_response(AppId, InteractionToken, Message, Token) ->
    Path = iolist_to_binary([
        ~"/webhooks/", snowflake(AppId), ~"/", url_token(InteractionToken), ~"/messages/@original"
    ]),
    do_patch(Path, Message, Token).

-spec create_global_command(binary(), map(), binary()) -> {ok, map()} | {error, term()}.
create_global_command(AppId, Command, Token) ->
    Path = iolist_to_binary([~"/applications/", snowflake(AppId), ~"/commands"]),
    do_post(Path, Command, Token).

-spec create_guild_command(binary(), binary(), map(), binary()) -> {ok, map()} | {error, term()}.
create_guild_command(AppId, GuildId, Command, Token) ->
    Path = iolist_to_binary([
        ~"/applications/", snowflake(AppId), ~"/guilds/", snowflake(GuildId), ~"/commands"
    ]),
    do_post(Path, Command, Token).

-spec get_channel(binary(), binary()) -> {ok, map()} | {error, term()}.
get_channel(ChannelId, Token) ->
    do_get(iolist_to_binary([~"/channels/", snowflake(ChannelId)]), Token).

-spec get_guild(binary(), binary()) -> {ok, map()} | {error, term()}.
get_guild(GuildId, Token) ->
    do_get(iolist_to_binary([~"/guilds/", snowflake(GuildId)]), Token).

-doc """
Fetch the most recent messages in a channel or thread, newest first.

`Limit` is bounded 1..100 by Discord; an out-of-range value is a caller bug
and fails the guard. Clamp at the call site when the value comes from a user.
""".
-spec get_channel_messages(binary(), 1..100, binary()) -> {ok, [map()]} | {error, term()}.
get_channel_messages(ChannelId, Limit, Token) when
    is_integer(Limit), Limit >= 1, Limit =< ?MAX_MESSAGE_LIMIT
->
    Path = iolist_to_binary([
        ~"/channels/", snowflake(ChannelId), ~"/messages?limit=", integer_to_binary(Limit)
    ]),
    do_get_list(Path, Token).

-doc "Fetch a single message by id.".
-spec get_message(binary(), binary(), binary()) -> {ok, map()} | {error, term()}.
get_message(ChannelId, MessageId, Token) ->
    Path = iolist_to_binary([
        ~"/channels/", snowflake(ChannelId), ~"/messages/", snowflake(MessageId)
    ]),
    do_get(Path, Token).

-spec delete_message(binary(), binary(), binary()) -> ok | {error, term()}.
delete_message(ChannelId, MessageId, Token) ->
    Path = iolist_to_binary([
        ~"/channels/", snowflake(ChannelId), ~"/messages/", snowflake(MessageId)
    ]),
    do_delete(Path, Token).

%% Internal

%% Ids reach these functions from application code that may have taken them
%% from user input. They are interpolated straight into the request path, so
%% an unvalidated id containing "/" or ".." reaches a different Discord
%% endpoint entirely - still carrying the bot token.
snowflake(Id) when is_binary(Id), byte_size(Id) > 0, byte_size(Id) =< ?MAX_SNOWFLAKE_LEN ->
    case all_digits(Id) of
        true -> Id;
        false -> error({invalid_snowflake, Id})
    end;
snowflake(Id) ->
    error({invalid_snowflake, Id}).

url_token(Value) when
    is_binary(Value), byte_size(Value) > 0, byte_size(Value) =< ?MAX_URL_TOKEN_LEN
->
    case token_charset(Value) of
        true -> Value;
        false -> error({invalid_url_token, Value})
    end;
url_token(Value) ->
    error({invalid_url_token, Value}).

all_digits(<<>>) -> true;
all_digits(<<Digit, Rest/binary>>) when Digit >= $0, Digit =< $9 -> all_digits(Rest);
all_digits(_) -> false.

token_charset(<<>>) ->
    true;
token_charset(<<Char, Rest/binary>>) when
    Char >= $a, Char =< $z;
    Char >= $A, Char =< $Z;
    Char >= $0, Char =< $9;
    Char =:= $-;
    Char =:= $_
->
    token_charset(Rest);
token_charset(_) ->
    false.

do_get(Path, Token) ->
    case
        with_ratelimit(~"GET", Path, fun() ->
            denshi_http:request(get, Path, [], undefined, Token)
        end)
    of
        {ok, Status, _Headers, Body} when Status >= 200, Status < 300 ->
            case Body of
                <<>> -> {ok, #{}};
                _ -> {ok, denshi_codec:decode(Body)}
            end;
        {ok, Status, _Headers, Body} ->
            {error, {http, Status, Body}};
        {error, _} = Error ->
            Error
    end.

do_get_list(Path, Token) ->
    case
        with_ratelimit(~"GET", Path, fun() ->
            denshi_http:request(get, Path, [], undefined, Token)
        end)
    of
        {ok, Status, _Headers, Body} when Status >= 200, Status < 300 ->
            case Body of
                <<>> -> {ok, []};
                _ -> denshi_codec:decode_list(Body)
            end;
        {ok, Status, _Headers, Body} ->
            {error, {http, Status, Body}};
        {error, _} = Error ->
            Error
    end.

do_post(Path, Data, Token) ->
    Body = denshi_codec:encode(Data),
    case
        with_ratelimit(~"POST", Path, fun() ->
            denshi_http:request(post, Path, [], Body, Token)
        end)
    of
        {ok, Status, _Headers, RespBody} when Status >= 200, Status < 300 ->
            case RespBody of
                <<>> -> {ok, #{}};
                _ -> {ok, denshi_codec:decode(RespBody)}
            end;
        {ok, Status, _Headers, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, _} = Error ->
            Error
    end.

do_patch(Path, Data, Token) ->
    Body = denshi_codec:encode(Data),
    case
        with_ratelimit(~"PATCH", Path, fun() ->
            denshi_http:request(patch, Path, [], Body, Token)
        end)
    of
        {ok, Status, _Headers, RespBody} when Status >= 200, Status < 300 ->
            case RespBody of
                <<>> -> {ok, #{}};
                _ -> {ok, denshi_codec:decode(RespBody)}
            end;
        {ok, Status, _Headers, RespBody} ->
            {error, {http, Status, RespBody}};
        {error, _} = Error ->
            Error
    end.

do_delete(Path, Token) ->
    case
        with_ratelimit(~"DELETE", Path, fun() ->
            denshi_http:request(delete, Path, [], undefined, Token)
        end)
    of
        {ok, Status, _Headers, _Body} when Status >= 200, Status < 300 ->
            ok;
        {ok, Status, _Headers, Body} ->
            {error, {http, Status, Body}};
        {error, _} = Error ->
            Error
    end.

with_ratelimit(Method, Path, Fun) ->
    case denshi_ratelimit:acquire(Method, Path) of
        ok ->
            Result = Fun(),
            case Result of
                {ok, _Status, Headers, _Body} ->
                    denshi_ratelimit:update(Method, Path, Headers);
                _ ->
                    ok
            end,
            case Result of
                {ok, 429, Headers2, RetryBody} ->
                    RetryAfter =
                        case find_retry_after(Headers2) of
                            undefined ->
                                retry_after_from_body(RetryBody);
                            Ms ->
                                Ms
                        end,
                    timer:sleep(RetryAfter),
                    Fun();
                _ ->
                    Result
            end;
        {wait, Ms} ->
            timer:sleep(Ms),
            with_ratelimit(Method, Path, Fun)
    end.

retry_after_from_body(Body) ->
    try denshi_codec:decode(Body) of
        #{~"retry_after" := Secs} -> round(Secs * 1000);
        _ -> ?DEFAULT_RETRY_AFTER_MS
    catch
        _:_ -> ?DEFAULT_RETRY_AFTER_MS
    end.

find_retry_after(Headers) ->
    case lists:keyfind(~"retry-after", 1, Headers) of
        {_, Value} ->
            try
                round(binary_to_float(Value) * 1000)
            catch
                _:_ ->
                    try
                        binary_to_integer(Value) * 1000
                    catch
                        _:_ -> undefined
                    end
            end;
        false ->
            undefined
    end.
