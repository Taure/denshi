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
    delete_message/3
]).

-spec get_gateway_bot(binary()) -> {ok, map()} | {error, term()}.
get_gateway_bot(Token) ->
    do_get(~"/gateway/bot", Token).

-spec send_message(binary(), map(), binary()) -> {ok, map()} | {error, term()}.
send_message(ChannelId, Message, Token) ->
    Path = iolist_to_binary([~"/channels/", ChannelId, ~"/messages"]),
    do_post(Path, Message, Token).

-spec create_interaction_response(binary(), binary(), map(), binary()) ->
    {ok, map() | binary()} | {error, term()}.
create_interaction_response(InteractionId, InteractionToken, Response, Token) ->
    Path = iolist_to_binary([
        ~"/interactions/", InteractionId, ~"/", InteractionToken, ~"/callback"
    ]),
    do_post(Path, Response, Token).

-spec edit_original_response(binary(), binary(), map(), binary()) ->
    {ok, map()} | {error, term()}.
edit_original_response(AppId, InteractionToken, Message, Token) ->
    Path = iolist_to_binary([
        ~"/webhooks/", AppId, ~"/", InteractionToken, ~"/messages/@original"
    ]),
    do_patch(Path, Message, Token).

-spec create_global_command(binary(), map(), binary()) -> {ok, map()} | {error, term()}.
create_global_command(AppId, Command, Token) ->
    Path = iolist_to_binary([~"/applications/", AppId, ~"/commands"]),
    do_post(Path, Command, Token).

-spec create_guild_command(binary(), binary(), map(), binary()) -> {ok, map()} | {error, term()}.
create_guild_command(AppId, GuildId, Command, Token) ->
    Path = iolist_to_binary([
        ~"/applications/", AppId, ~"/guilds/", GuildId, ~"/commands"
    ]),
    do_post(Path, Command, Token).

-spec get_channel(binary(), binary()) -> {ok, map()} | {error, term()}.
get_channel(ChannelId, Token) ->
    do_get(iolist_to_binary([~"/channels/", ChannelId]), Token).

-spec get_guild(binary(), binary()) -> {ok, map()} | {error, term()}.
get_guild(GuildId, Token) ->
    do_get(iolist_to_binary([~"/guilds/", GuildId]), Token).

-spec delete_message(binary(), binary(), binary()) -> ok | {error, term()}.
delete_message(ChannelId, MessageId, Token) ->
    Path = iolist_to_binary([~"/channels/", ChannelId, ~"/messages/", MessageId]),
    do_delete(Path, Token).

%% Internal

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
                                case catch denshi_codec:decode(RetryBody) of
                                    #{~"retry_after" := Secs} -> round(Secs * 1000);
                                    _ -> 1000
                                end;
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
