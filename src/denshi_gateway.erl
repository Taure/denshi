-module(denshi_gateway).
-behaviour(gen_statem).

-export([start_link/1, get_session/0]).
-export([init/1, callback_mode/0, terminate/3]).
-export([disconnected/3, connecting/3, connected/3, identified/3, resuming/3]).

-include("denshi.hrl").

-record(data, {
    config :: map(),
    session :: #denshi_session{},
    gun_pid :: pid() | undefined,
    gun_ref :: reference() | undefined,
    stream_ref :: reference() | undefined,
    reconnect_attempts = 0 :: non_neg_integer(),
    gateway_url :: binary() | undefined
}).

-define(MAX_RECONNECT_DELAY, 60_000).
-define(GATEWAY_VERSION, ~"10").
-define(GATEWAY_ENCODING, ~"json").

%% API

-spec start_link(map()) -> gen_statem:start_ret().
start_link(Config) ->
    gen_statem:start_link({local, ?MODULE}, ?MODULE, Config, []).

-spec get_session() -> {ok, #denshi_session{}} | {error, not_connected}.
get_session() ->
    gen_statem:call(?MODULE, get_session).

%% gen_statem callbacks

callback_mode() ->
    [state_functions, state_enter].

init(#{token := Token, intents := Intents} = Config) ->
    IntentBitmask = denshi_intent:combine(Intents),
    Session = #denshi_session{
        token = Token,
        intents = IntentBitmask
    },
    GatewayUrl = maps:get(gateway_url, Config, undefined),
    {ok, disconnected, #data{
        config = Config,
        session = Session,
        gateway_url = GatewayUrl
    }}.

terminate(_Reason, _State, #data{gun_pid = undefined}) ->
    ok;
terminate(_Reason, _State, #data{gun_pid = GunPid, gun_ref = GunRef}) ->
    demonitor(GunRef, [flush]),
    gun:close(GunPid),
    ok.

%% State: disconnected

disconnected(enter, _OldState, #data{reconnect_attempts = 0} = Data) ->
    {keep_state, Data, [{state_timeout, 0, connect}]};
disconnected(enter, _OldState, #data{reconnect_attempts = N} = Data) ->
    Delay = min(?MAX_RECONNECT_DELAY, (1 bsl min(N, 10)) * 100),
    Jitter = rand:uniform(max(1, Delay div 2)),
    logger:info(~"Discord gateway: reconnecting in ~Bms (attempt ~B)", [Delay + Jitter, N]),
    {keep_state, Data, [{state_timeout, Delay + Jitter, connect}]};
disconnected(state_timeout, connect, Data) ->
    case resolve_gateway_url(Data) of
        {ok, Url, Data1} ->
            case open_websocket(Url) of
                {ok, GunPid, GunRef, StreamRef} ->
                    {next_state, connecting, Data1#data{
                        gun_pid = GunPid,
                        gun_ref = GunRef,
                        stream_ref = StreamRef
                    }};
                {error, Reason} ->
                    logger:error(~"Discord gateway: connection failed: ~p", [Reason]),
                    N = Data1#data.reconnect_attempts,
                    {keep_state, Data1#data{reconnect_attempts = N + 1}, [
                        {state_timeout, 0, connect}
                    ]}
            end;
        {error, Reason} ->
            logger:error(~"Discord gateway: failed to get gateway URL: ~p", [Reason]),
            N = Data#data.reconnect_attempts,
            {keep_state, Data#data{reconnect_attempts = N + 1}, [{state_timeout, 0, connect}]}
    end;
disconnected({call, From}, get_session, _Data) ->
    {keep_state_and_data, [{reply, From, {error, not_connected}}]};
disconnected(info, _, _Data) ->
    keep_state_and_data.

%% State: connecting

connecting(enter, _OldState, _Data) ->
    {keep_state_and_data, [{state_timeout, 15_000, upgrade_timeout}]};
connecting(
    info,
    {gun_upgrade, GunPid, StreamRef, [~"websocket"], _Headers},
    #data{gun_pid = GunPid, stream_ref = StreamRef} = Data
) ->
    logger:debug(~"Discord gateway: WebSocket upgrade successful"),
    {next_state, connected, Data};
connecting(
    info,
    {gun_response, GunPid, StreamRef, _, Status, _Headers},
    #data{gun_pid = GunPid, stream_ref = StreamRef} = Data
) ->
    logger:error(~"Discord gateway: upgrade failed with HTTP ~B", [Status]),
    close_connection(Data),
    N = Data#data.reconnect_attempts,
    {next_state, disconnected, Data#data{
        gun_pid = undefined,
        gun_ref = undefined,
        stream_ref = undefined,
        reconnect_attempts = N + 1
    }};
connecting(
    info,
    {gun_error, GunPid, _StreamRef, Reason},
    #data{gun_pid = GunPid} = Data
) ->
    logger:error(~"Discord gateway: gun error during upgrade: ~p", [Reason]),
    close_connection(Data),
    N = Data#data.reconnect_attempts,
    {next_state, disconnected, Data#data{
        gun_pid = undefined,
        gun_ref = undefined,
        stream_ref = undefined,
        reconnect_attempts = N + 1
    }};
connecting(
    info,
    {'DOWN', GunRef, process, GunPid, Reason},
    #data{gun_pid = GunPid, gun_ref = GunRef} = Data
) ->
    logger:error(~"Discord gateway: gun process down during upgrade: ~p", [Reason]),
    N = Data#data.reconnect_attempts,
    {next_state, disconnected, Data#data{
        gun_pid = undefined,
        gun_ref = undefined,
        stream_ref = undefined,
        reconnect_attempts = N + 1
    }};
connecting(state_timeout, upgrade_timeout, Data) ->
    logger:error(~"Discord gateway: WebSocket upgrade timed out"),
    close_connection(Data),
    N = Data#data.reconnect_attempts,
    {next_state, disconnected, Data#data{
        gun_pid = undefined,
        gun_ref = undefined,
        stream_ref = undefined,
        reconnect_attempts = N + 1
    }};
connecting({call, From}, get_session, _Data) ->
    {keep_state_and_data, [{reply, From, {error, not_connected}}]};
connecting(info, _, _Data) ->
    keep_state_and_data.

%% State: connected (waiting for Hello)

connected(enter, _OldState, _Data) ->
    {keep_state_and_data, [{state_timeout, 10_000, hello_timeout}]};
connected(
    info,
    {gun_ws, GunPid, StreamRef, {text, Frame}},
    #data{gun_pid = GunPid, stream_ref = StreamRef} = Data
) ->
    Event = denshi_event:parse(denshi_codec:decode(Frame)),
    case Event#denshi_event.op of
        10 ->
            #{~"heartbeat_interval" := Interval} = Event#denshi_event.data,
            denshi_heartbeat:start_beating(self(), Interval),
            Session = Data#data.session,
            case Session#denshi_session.session_id of
                undefined ->
                    send_identify(Data),
                    {next_state, identified, Data#data{reconnect_attempts = 0}};
                _SessionId ->
                    send_resume(Data),
                    {next_state, resuming, Data#data{reconnect_attempts = 0}}
            end;
        _ ->
            logger:warning(~"Discord gateway: unexpected op ~B in connected state", [
                Event#denshi_event.op
            ]),
            keep_state_and_data
    end;
connected(state_timeout, hello_timeout, Data) ->
    logger:error(~"Discord gateway: Hello timeout"),
    close_connection(Data),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
connected(info, Msg, Data) ->
    handle_common_info(Msg, connected, Data).

%% State: identified (normal operation)

identified(enter, _OldState, _Data) ->
    keep_state_and_data;
identified(
    info,
    {gun_ws, GunPid, StreamRef, {text, Frame}},
    #data{gun_pid = GunPid, stream_ref = StreamRef} = Data
) ->
    Event = denshi_event:parse(denshi_codec:decode(Frame)),
    handle_gateway_event(Event, Data);
identified(info, send_heartbeat, Data) ->
    send_heartbeat(Data),
    keep_state_and_data;
identified(info, zombie_connection, Data) ->
    logger:warning(~"Discord gateway: zombie connection detected, reconnecting"),
    close_connection(Data),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
identified({call, From}, get_session, #data{session = Session}) ->
    {keep_state_and_data, [{reply, From, {ok, Session}}]};
identified(info, Msg, Data) ->
    handle_common_info(Msg, identified, Data).

%% State: resuming

resuming(enter, _OldState, _Data) ->
    {keep_state_and_data, [{state_timeout, 15_000, resume_timeout}]};
resuming(
    info,
    {gun_ws, GunPid, StreamRef, {text, Frame}},
    #data{gun_pid = GunPid, stream_ref = StreamRef} = Data
) ->
    Event = denshi_event:parse(denshi_codec:decode(Frame)),
    case Event of
        #denshi_event{op = 0, name = resumed} ->
            logger:info(~"Discord gateway: resumed successfully"),
            {next_state, identified, Data};
        #denshi_event{op = 9} ->
            logger:warning(~"Discord gateway: invalid session during resume, re-identifying"),
            Session = Data#data.session,
            NewSession = Session#denshi_session{session_id = undefined, resume_url = undefined},
            send_identify(Data#data{session = NewSession}),
            {next_state, identified, Data#data{session = NewSession}};
        _ ->
            handle_gateway_event(Event, Data)
    end;
resuming(state_timeout, resume_timeout, Data) ->
    logger:warning(~"Discord gateway: resume timed out, re-identifying"),
    Session = Data#data.session,
    NewSession = Session#denshi_session{session_id = undefined, resume_url = undefined},
    send_identify(Data#data{session = NewSession}),
    {next_state, identified, Data#data{session = NewSession}};
resuming(info, send_heartbeat, Data) ->
    send_heartbeat(Data),
    keep_state_and_data;
resuming({call, From}, get_session, _Data) ->
    {keep_state_and_data, [{reply, From, {error, not_connected}}]};
resuming(info, Msg, Data) ->
    handle_common_info(Msg, resuming, Data).

%% Internal: event handling

handle_gateway_event(#denshi_event{op = 0, name = Name, data = EventData, sequence = Seq}, Data) ->
    Session = Data#data.session,
    NewSession =
        case Seq of
            undefined -> Session;
            _ -> Session#denshi_session{sequence = Seq}
        end,
    NewData =
        case Name of
            ready ->
                SessId = maps:get(~"session_id", EventData, undefined),
                ResumeUrl = maps:get(~"resume_gateway_url", EventData, undefined),
                logger:info(~"Discord gateway: READY (session: ~ts)", [SessId]),
                Data#data{
                    session = NewSession#denshi_session{
                        session_id = SessId,
                        resume_url = ResumeUrl
                    }
                };
            _ ->
                Data#data{session = NewSession}
        end,
    denshi_dispatcher:dispatch(Name, EventData),
    {keep_state, NewData};
handle_gateway_event(#denshi_event{op = 1}, Data) ->
    send_heartbeat(Data),
    keep_state_and_data;
handle_gateway_event(#denshi_event{op = 7}, Data) ->
    logger:info(~"Discord gateway: server requested reconnect"),
    close_connection(Data),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
handle_gateway_event(#denshi_event{op = 9, data = Resumable}, Data) ->
    Session = Data#data.session,
    case Resumable of
        false ->
            logger:warning(~"Discord gateway: invalid session (not resumable)"),
            NewSession = Session#denshi_session{session_id = undefined, resume_url = undefined},
            timer:sleep(1000 + rand:uniform(4000)),
            send_identify(Data#data{session = NewSession}),
            {keep_state, Data#data{session = NewSession}};
        _ ->
            logger:info(~"Discord gateway: invalid session (resumable)"),
            timer:sleep(1000 + rand:uniform(4000)),
            send_resume(Data),
            {next_state, resuming, Data}
    end;
handle_gateway_event(#denshi_event{op = 11}, _Data) ->
    denshi_heartbeat:ack(),
    keep_state_and_data;
handle_gateway_event(#denshi_event{op = Op}, _Data) ->
    logger:debug(~"Discord gateway: unhandled opcode ~B", [Op]),
    keep_state_and_data.

handle_common_info(
    {'DOWN', GunRef, process, GunPid, Reason},
    _StateName,
    #data{gun_pid = GunPid, gun_ref = GunRef} = Data
) ->
    logger:error(~"Discord gateway: gun process down: ~p", [Reason]),
    denshi_heartbeat:stop_beating(),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
handle_common_info(
    {gun_ws, GunPid, _StreamRef, {close, Code, Reason}},
    _StateName,
    #data{gun_pid = GunPid} = Data
) ->
    logger:warning(~"Discord gateway: WebSocket closed (~B): ~ts", [Code, Reason]),
    denshi_heartbeat:stop_beating(),
    close_connection(Data),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
handle_common_info(
    {gun_error, GunPid, _StreamRef, Reason},
    _StateName,
    #data{gun_pid = GunPid} = Data
) ->
    logger:error(~"Discord gateway: gun error: ~p", [Reason]),
    denshi_heartbeat:stop_beating(),
    close_connection(Data),
    {next_state, disconnected, Data#data{
        gun_pid = undefined, gun_ref = undefined, stream_ref = undefined
    }};
handle_common_info(_Msg, _StateName, _Data) ->
    keep_state_and_data.

%% Internal: connection helpers

resolve_gateway_url(#data{gateway_url = undefined, session = Session} = Data) ->
    case denshi_rest:get_gateway_bot(Session#denshi_session.token) of
        {ok, #{~"url" := Url}} ->
            {ok, Url, Data#data{gateway_url = Url}};
        {error, _} = Error ->
            Error
    end;
resolve_gateway_url(#data{session = #denshi_session{resume_url = ResumeUrl}} = Data) when
    ResumeUrl =/= undefined
->
    {ok, ResumeUrl, Data};
resolve_gateway_url(#data{gateway_url = Url} = Data) ->
    {ok, Url, Data}.

open_websocket(Url) ->
    #{host := Host} = uri_string:parse(Url),
    Port = 443,
    Path = iolist_to_binary([
        ~"/?v=",
        ?GATEWAY_VERSION,
        ~"&encoding=",
        ?GATEWAY_ENCODING
    ]),
    case
        gun:open(binary_to_list(Host), Port, #{
            protocols => [http],
            transport => tls,
            tls_opts => [
                {verify, verify_peer},
                {cacerts, public_key:cacerts_get()},
                {alpn_advertised_protocols, [<<"http/1.1">>]}
            ]
        })
    of
        {ok, GunPid} ->
            GunRef = monitor(process, GunPid),
            case gun:await_up(GunPid, 10_000) of
                {ok, _Protocol} ->
                    StreamRef = gun:ws_upgrade(GunPid, Path, []),
                    {ok, GunPid, GunRef, StreamRef};
                {error, Reason} ->
                    demonitor(GunRef, [flush]),
                    gun:close(GunPid),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

close_connection(#data{gun_pid = undefined}) ->
    ok;
close_connection(#data{gun_pid = GunPid, gun_ref = GunRef}) ->
    demonitor(GunRef, [flush]),
    gun:close(GunPid),
    ok.

send_identify(#data{session = Session} = Data) ->
    Payload = #{
        ~"token" => Session#denshi_session.token,
        ~"intents" => Session#denshi_session.intents,
        ~"properties" => #{
            ~"os" => iolist_to_binary([
                atom_to_list(element(1, os:type())), "/", atom_to_list(element(2, os:type()))
            ]),
            ~"browser" => ~"denshi",
            ~"device" => ~"denshi"
        }
    },
    send_frame(Data, denshi_codec:gateway_frame(2, Payload)).

send_resume(#data{session = Session} = Data) ->
    Payload = #{
        ~"token" => Session#denshi_session.token,
        ~"session_id" => Session#denshi_session.session_id,
        ~"seq" => Session#denshi_session.sequence
    },
    send_frame(Data, denshi_codec:gateway_frame(6, Payload)).

send_heartbeat(Data) ->
    Seq = (Data#data.session)#denshi_session.sequence,
    send_frame(Data, denshi_codec:gateway_frame(1, Seq)).

send_frame(#data{gun_pid = GunPid, stream_ref = StreamRef}, Frame) ->
    gun:ws_send(GunPid, StreamRef, {text, Frame}).
