-module(denshi).

-export([start/1, stop/0]).
-export([send_message/2, create_command/2, create_guild_command/3]).
-export([respond/2, defer/1, edit_response/2]).

-include("denshi.hrl").

-spec start(map()) -> {ok, pid()} | {error, term()}.
start(#{token := _} = Config) ->
    {ok, _} = application:ensure_all_started(gun),
    denshi_sup:start_link(Config).

-spec stop() -> ok.
stop() ->
    case whereis(denshi_sup) of
        undefined ->
            ok;
        Pid ->
            exit(Pid, shutdown),
            ok
    end.

-spec send_message(binary(), binary() | map()) -> {ok, map()} | {error, term()}.
send_message(ChannelId, Content) when is_binary(Content) ->
    send_message(ChannelId, #{~"content" => Content});
send_message(ChannelId, Message) when is_map(Message) ->
    Token = get_token(),
    denshi_rest:send_message(ChannelId, Message, Token).

-spec create_command(binary(), map()) -> {ok, map()} | {error, term()}.
create_command(AppId, Command) ->
    Token = get_token(),
    denshi_rest:create_global_command(AppId, Command, Token).

-spec create_guild_command(binary(), binary(), map()) -> {ok, map()} | {error, term()}.
create_guild_command(AppId, GuildId, Command) ->
    Token = get_token(),
    denshi_rest:create_guild_command(AppId, GuildId, Command, Token).

-spec respond(#denshi_interaction{}, map()) -> {ok, map() | binary()} | {error, term()}.
respond(#denshi_interaction{id = Id, token = IToken}, Response) ->
    Token = get_token(),
    denshi_rest:create_interaction_response(Id, IToken, Response, Token).

-spec defer(#denshi_interaction{}) -> {ok, map() | binary()} | {error, term()}.
defer(Interaction) ->
    respond(Interaction, denshi_interaction:deferred_message()).

-spec edit_response(#denshi_interaction{}, map()) -> {ok, map()} | {error, term()}.
edit_response(#denshi_interaction{application_id = AppId, token = IToken}, Message) ->
    Token = get_token(),
    denshi_rest:edit_original_response(AppId, IToken, Message, Token).

%% Internal

get_token() ->
    {ok, Session} = denshi_gateway:get_session(),
    Session#denshi_session.token.
