%%%-------------------------------------------------------------------
%%% @author derry6
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 4月 2020 1:50 下午
%%%-------------------------------------------------------------------

-module(emqx_rabbit_hook_env).
-author("derry6").

-include("emqx_rabbit_hook.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("amqp_client/include/amqp_client_internal.hrl").

-define(DEFAULT_EXCHANGE_TYPE, <<"topic">>).
-define(DEFAULT_EXCHANGE, <<"emqx.client.events">>).

%% API
-export([rabbit_params/1, hook_rules/0, payload_encoding/0]).

rabbit_params(Opts) ->
  Params = #amqp_params_network{
    host = proplists:get_value(host, Opts),
    port = proplists:get_value(port, Opts),
    username = list_to_binary(proplists:get_value(username, Opts)),
    password = list_to_binary(proplists:get_value(password, Opts)),
    virtual_host = list_to_binary(proplists:get_value(virtual_host, Opts))
  },
  {ok, Params}.

hook_rules() ->
  Rules = application:get_env(?APP, rules, []),
  parse_rule(Rules).


parse_rule(Rules) -> parse_rule(Rules, []).
parse_rule([], Acc) -> lists:reverse(Acc);
parse_rule([{Rule, Conf} | Rules], Acc) ->
  Params = emqx_json:decode(iolist_to_binary(Conf)),
  Type = proplists:get_value(<<"type">>, Params, ?DEFAULT_EXCHANGE_TYPE),
  Exchange = proplists:get_value(<<"exchange">>, Params, ?DEFAULT_EXCHANGE),
  Routing = proplists:get_value(<<"routing">>, Params, list_to_binary(Rule)),
  Filter = proplists:get_value(<<"topic">>, Params),
  Env = #{type => Type, exchange => Exchange, routing => Routing, filter => Filter},
  io:format("Rule: ~p  type=~p, exchange=~p, routing=~p, filter=~p~n", [Rule, Type, Exchange, Routing, Filter]),
  parse_rule(Rules, [{list_to_atom(Rule), Env} | Acc]).


payload_encoding() -> application:get_env(?APP, encode_payload, undefined).
