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

get_ssl_options(Enabled) when Enabled == on ->
  Opts = [
    {cacertfile, application:get_env(?APP, ssl_cacertfile, "")},
    {certfile, application:get_env(?APP, ssl_certfile, "")},
    {keyfile, application:get_env(?APP, ssl_keyfile, "")}
  ],
  case application:get_env(?APP, ssl_verify_peer, off) of
    on -> [{verify, verify_peer} | Opts];
    _ -> Opts
  end;
get_ssl_options(_) -> none.

rabbit_params(Opts) ->
  Params = #amqp_params_network{
    host = proplists:get_value(host, Opts),
    port = proplists:get_value(port, Opts),
    username = list_to_binary(proplists:get_value(username, Opts)),
    password = list_to_binary(proplists:get_value(password, Opts)),
    virtual_host = list_to_binary(proplists:get_value(virtual_host, Opts)),
    channel_max = proplists:get_value(channel_max, Opts),
    frame_max = proplists:get_value(frame_max, Opts),
    connection_timeout =  proplists:get_value(connection_timeout, Opts),
    ssl_options = get_ssl_options(application:get_env(?APP, ssl_enabled, off))
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
  ?LOG(info, "Rule: ~p  type=~p, exchange=~p, routing=~p, filter=~p", [Rule, Type, Exchange, Routing, Filter]),
  parse_rule(Rules, [{list_to_atom(Rule), Env} | Acc]).


payload_encoding() -> application:get_env(?APP, encode_payload, undefined).
