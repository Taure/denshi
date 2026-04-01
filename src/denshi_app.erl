-module(denshi_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    case application:get_env(denshi, token) of
        {ok, _} ->
            Config = normalize(maps:from_list(application:get_all_env(denshi))),
            denshi_sup:start_link(Config);
        undefined ->
            {ok,
                spawn_link(fun() ->
                    receive
                        stop -> ok
                    end
                end)}
    end.

stop(_State) ->
    ok.

normalize(#{token := Token} = Config) when is_list(Token) ->
    Config#{token := unicode:characters_to_binary(Token)};
normalize(Config) ->
    Config.
