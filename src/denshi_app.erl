-module(denshi_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Config = application:get_all_env(denshi),
    denshi_sup:start_link(maps:from_list(Config)).

stop(_State) ->
    ok.
