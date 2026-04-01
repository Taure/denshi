-module(denshi_http).

-export([request/5, request/6]).

-define(BASE_URL, "https://discord.com/api/v10").
-define(USER_AGENT, ~"DiscordBot (denshi, 0.1.0)").

-type method() :: get | post | put | patch | delete.
-type headers() :: [{binary(), binary()}].
-type response() :: {ok, pos_integer(), headers(), binary()} | {error, term()}.

-spec request(method(), binary(), headers(), binary() | undefined, binary()) -> response().
request(Method, Path, Headers, Body, Token) ->
    request(Method, Path, Headers, Body, Token, 10_000).

-spec request(method(), binary(), headers(), binary() | undefined, binary(), timeout()) ->
    response().
request(Method, Path, ExtraHeaders, Body, Token, Timeout) ->
    Host = ~"discord.com",
    Port = 443,
    case gun:open(binary_to_list(Host), Port, #{protocols => [http], transport => tls}) of
        {ok, ConnPid} ->
            MonRef = monitor(process, ConnPid),
            try
                case gun:await_up(ConnPid, Timeout) of
                    {ok, _Protocol} ->
                        do_request(
                            ConnPid, MonRef, Method, Path, ExtraHeaders, Body, Token, Timeout
                        );
                    {error, Reason} ->
                        {error, Reason}
                end
            after
                demonitor(MonRef, [flush]),
                gun:close(ConnPid)
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_request(ConnPid, MonRef, Method, Path, ExtraHeaders, Body, Token, Timeout) ->
    FullPath = iolist_to_binary([~"/api/v10", Path]),
    BaseHeaders = [
        {~"authorization", iolist_to_binary([~"Bot ", Token])},
        {~"user-agent", ?USER_AGENT},
        {~"content-type", ~"application/json"}
    ],
    Headers = BaseHeaders ++ ExtraHeaders,
    StreamRef =
        case Body of
            undefined ->
                gun:headers(ConnPid, method_to_binary(Method), FullPath, Headers);
            _ ->
                gun:request(ConnPid, method_to_binary(Method), FullPath, Headers, Body)
        end,
    await_response(ConnPid, MonRef, StreamRef, Timeout).

await_response(ConnPid, MonRef, StreamRef, Timeout) ->
    receive
        {gun_response, ConnPid, StreamRef, fin, Status, RespHeaders} ->
            {ok, Status, RespHeaders, <<>>};
        {gun_response, ConnPid, StreamRef, nofin, Status, RespHeaders} ->
            case await_body(ConnPid, MonRef, StreamRef, Timeout) of
                {ok, RespBody} ->
                    {ok, Status, RespHeaders, RespBody};
                {error, _} = Error ->
                    Error
            end;
        {'DOWN', MonRef, process, ConnPid, Reason} ->
            {error, {gun_down, Reason}}
    after Timeout ->
        {error, timeout}
    end.

await_body(ConnPid, MonRef, StreamRef, Timeout) ->
    await_body(ConnPid, MonRef, StreamRef, Timeout, []).

await_body(ConnPid, MonRef, StreamRef, Timeout, Acc) ->
    receive
        {gun_data, ConnPid, StreamRef, fin, Data} ->
            {ok, iolist_to_binary(lists:reverse([Data | Acc]))};
        {gun_data, ConnPid, StreamRef, nofin, Data} ->
            await_body(ConnPid, MonRef, StreamRef, Timeout, [Data | Acc]);
        {'DOWN', MonRef, process, ConnPid, Reason} ->
            {error, {gun_down, Reason}}
    after Timeout ->
        {error, timeout}
    end.

method_to_binary(get) -> ~"GET";
method_to_binary(post) -> ~"POST";
method_to_binary(put) -> ~"PUT";
method_to_binary(patch) -> ~"PATCH";
method_to_binary(delete) -> ~"DELETE".
