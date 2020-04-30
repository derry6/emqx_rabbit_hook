-module(emqx_rabbit_hook_cli).

-behaviour(ecpool_worker).

% Include libraries
-include("emqx_rabbit_hook.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("emqx/include/logger.hrl").

-export([connect/1, ensure_exchange/2, pub/3]).

connect(Opts) ->
  {ok, Params} = emqx_rabbit_hook_env:rabbit_params(Opts),
  ?LOG(info, "Connecting ~p", [Params]),
  case amqp_connection:start(Params) of
    {ok, Conn} ->
      ?LOG(info, "Connected: ~p", [Conn]),
      {ok, Conn};
    {error, Error} ->
      ?LOG(error, "Can't connect to mqtt broker: ~p", [Error]),
      {error, Error}
  end.

ensure_exchange(Conn, Type, Name) ->
  {ok, Channel} = amqp_connection:open_channel(Conn),
  amqp_channel:call(Channel, #'exchange.declare'{
    exchange = Name,
    type = Type,
    durable = true}),
  ok = amqp_channel:close(Channel),
  ok.

ensure_exchange(Type, Name) ->
  ecpool:with_client(?APP,
    fun(Conn) ->
      ensure_exchange(Conn, Type, Name)
    end).

% 是否需要每次都 Open channel ??
pub(Exchange, RoutingKey, Payload) ->
  ecpool:with_client(?APP,
    fun(Conn) ->
      {ok, Channel} = amqp_connection:open_channel(Conn),
      ok = amqp_channel:cast(
        Channel,
        #'basic.publish'{exchange = Exchange, routing_key = RoutingKey},
        #amqp_msg{props = #'P_basic'{delivery_mode = 2}, payload = Payload}
      ),
      ?LOG(debug, "Message published, exchange = ~p, routing = ~p", [Exchange, RoutingKey]),
      ok = amqp_channel:close(Channel),
      ok
    end
  ).