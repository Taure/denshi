-module(denshi_codec).

-export([encode/1, decode/1, gateway_frame/2, gateway_frame/3]).

-include("denshi.hrl").

-spec encode(term()) -> binary().
encode(Term) ->
    iolist_to_binary(json:encode(Term)).

-spec decode(binary()) -> map().
decode(Bin) ->
    json:decode(Bin).

-spec gateway_frame(non_neg_integer(), term()) -> binary().
gateway_frame(Op, Data) ->
    encode(#{~"op" => Op, ~"d" => Data}).

-spec gateway_frame(non_neg_integer(), term(), non_neg_integer() | undefined) -> binary().
gateway_frame(Op, Data, undefined) ->
    gateway_frame(Op, Data);
gateway_frame(Op, Data, Sequence) ->
    encode(#{~"op" => Op, ~"d" => Data, ~"s" => Sequence}).
