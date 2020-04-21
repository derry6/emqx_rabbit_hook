
-define(APP, emqx_rabbit_hook).

-record(pub_rule, {
    exchange = <<"">>,
    exchange_type = <<"">>,
    routing_key = <<"">>
}).
