%%
%% Copyright (C) 2014, Jaguar Land Rover
%%
%% This program is licensed under the terms and conditions of the
%% Mozilla Public License, version 2.0.  The full text of the
%% Mozilla Public License is at https://www.mozilla.org/MPL/2.0/
%%


-module(authorize_rpc).
-behaviour(gen_server).

-export([handle_rpc/2,
	 handle_notification/2]).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-export([start_json_server/0]).
-export([get_authorize_jwt/1,
	 get_certificates/1,
	 sign_message/2,
	 validate_message/3,
	 validate_authorization/3,
	 validate_authorization/4,
	 store_certs/3,
	 authorize_local_message/3,
	 authorize_remote_message/3]).
-export([filter_by_service/3]).

%% for testing & development
-export([sign/1]).
-export([public_key/0, public_key_json/0,
	 private_key/0]).

-include_lib("lager/include/log.hrl").
-include_lib("rvi_common/include/rvi_common.hrl").

-define(SERVER, ?MODULE).
-record(st, {
	  next_transaction_id = 1, %% Sequentially incremented transaction id.
	  services_tid = undefined, %% Known services.
	  cs = #component_spec{},
	  private_key = undefined,
	  public_key = undefined
	 }).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    ?debug("authorize_rpc:init(): called."),
    {Priv, Pub} =  authorize_keys:get_key_pair(),
    ?debug("KeyPair = {~s, ~s}~n", [authorize_keys:pp_key(Priv),
				    authorize_keys:pp_key(Pub)]),
    {ok, #st { cs = rvi_common:get_component_specification(),
	       private_key = Priv,
	       public_key = Pub} }.

start_json_server() ->
    ?debug("authorize_rpc:start_json_server(): called"),
    rvi_common:start_json_rpc_server(authorize, ?MODULE, authorize_sup),
    ok.

sign_message(CompSpec, Message) ->
    ?debug("authorize_rpc:sign_message()~n", []),
    rvi_common:request(authorize, ?MODULE, sign_message,
		       [{message, Message}], [status, jwt], CompSpec).

validate_message(CompSpec, JWT, Conn) ->
    ?debug("authorize_rpc:validate_message()~n", []),
    rvi_common:request(authorize, ?MODULE, validate_message,
		       [{jwt, JWT},
			{conn, Conn}], [status, message], CompSpec).

get_authorize_jwt(CompSpec) ->
    ?debug("authorize_rpc:get_authorize_jwt()~n", []),
    rvi_common:request(authorize, ?MODULE, get_authorize_jwt,
		       [], [status, jwt], CompSpec).

get_certificates(CompSpec) ->
    ?debug("authorize_rpc:get_certificates()~n", []),
    rvi_common:request(authorize, ?MODULE, get_certificates,
		       [], [status, certs], CompSpec).

validate_authorization(CompSpec, JWT, Conn) ->
    ?debug("authorize_rpc:validate_authorization():"
	   " Conn = ~p~n", [Conn]),
    rvi_common:request(authorize, ?MODULE, validate_authorization,
		       [{jwt, JWT},
			{conn, Conn}],
		       [status], CompSpec).

validate_authorization(CompSpec, JWT, Certs, Conn) ->
    ?debug("authorize_rpc:validate_authorization():"
	   " Conn = ~p~n", [Conn]),
    rvi_common:request(authorize, ?MODULE, validate_authorization,
		       [{jwt, JWT},
			{certs, Certs},
			{conn, Conn}],
		       [status], CompSpec).

store_certs(CompSpec, Certs, Conn) ->
    rvi_common:request(authorize, ?MODULE, store_certs,
		       [{certs, Certs},
			{conn, Conn}],
		       [status], CompSpec).

authorize_local_message(CompSpec, Service, Params) ->
    ?debug("authorize_rpc:authorize_local_msg(): params:    ~p ~n", [Params]),
    rvi_common:request(authorize, ?MODULE, authorize_local_message,
		       [{service, Service},
			{parameters, Params}],
		       [status], CompSpec).

authorize_remote_message(CompSpec, Service, Params) ->
    ?debug("authorize_rpc:authorize_remote_msg(): service: ~p ~n", [Service]),
    ?debug("authorize_rpc:authorize_remote_msg(): parameters: ~p ~n", [Params]),
    rvi_common:request(authorize, ?MODULE,authorize_remote_message,
		       [{service, Service},
			{parameters, Params}],
		       [status], CompSpec).

filter_by_service(CompSpec, Services, Conn) ->
    ?debug("authorize_rpc:filter_by_service(): services: ~p ~n", [Services]),
    ?debug("authorize_rpc:filter_by_service(): conn: ~p ~n", [Conn]),
    rvi_common:request(authorize, ?MODULE, filter_by_service,
		       [{ services, Services },
			{ conn, Conn }],
		       [status, services], CompSpec).

%% For testing while developing cert functionality
sign(Term) ->
    %% Use private key of authorize_rpc to make a JWT token
    gen_server:call(?SERVER, {sign, Term}).

public_key() ->
    gen_server:call(?SERVER, public_key).

public_key_json() ->
    gen_server:call(?SERVER, public_key_json).

private_key() ->
    gen_server:call(?SERVER, private_key).

%% JSON-RPC entry point
%% CAlled by local exo http server
handle_rpc("sign_message", Args) ->
    {ok, Message} = rvi_common:get_json_element(["message"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status, JWT ] =
	gen_server:call(?SERVER, { rvi, sign_message, [Message, LogId] }),
    ?debug("Message signature = ~p~n", [JWT]),
    {ok, [ {status, rvi_common:json_rpc_status(Status)},
	   {jwt, JWT} ]};
handle_rpc("validate_message", Args) ->
    ?debug("validate_message; Args = ~p~n", [Args]),
    {ok, JWT} = rvi_common:get_json_element(["jwt"], Args),
    {ok, Conn} = rvi_common:get_json_element(["conn"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status, Msg ] =
	gen_server:call(?SERVER, { rvi, validate_message, [JWT, Conn, LogId] }),
    {ok, [ {status, rvi_common:json_rpc_status(Status)},
	   {message, Msg} ]};
handle_rpc("get_authorize_jwt", Args) ->
    LogId = rvi_common:get_json_log_id(Args),
    [ Status | Rem ] =
	gen_server:call(?SERVER, { rvi, get_authorize_jwt, [LogId] }),
    {ok, [ rvi_common:json_rpc_status(Status) | Rem ] };
handle_rpc("get_certificates", Args) ->
    LogId = rvi_common:get_json_log_id(Args),
    [ Status | Rem ] =
	gen_server:call(?SERVER, { rvi, get_certificates, [LogId] }),
    {ok, [ rvi_common:json_rpc_status(Status) | Rem ] };
handle_rpc("validate_authorization", Args) ->
    {ok, JWT} = rvi_common:get_json_element(["jwt"], Args),
    {ok, Conn} = rvi_common:get_json_element(["connection"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    CmdArgs =
	case rvi_common:get_json_element(["certs"], Args) of
	    {ok, Certs} -> [JWT, Certs, Conn, LogId];
	    {error, _}  -> [JWT, Conn, LogId]
	end,
    [ Status | Rem ] =
	gen_server:call(?SERVER, {rvi, validate_authorization, CmdArgs}),
    {ok, [ rvi_common:json_rpc_status(Status) | Rem] };
handle_rpc("store_certs", Args) ->
    {ok, Certs} = rvi_common:get_json_element(["certs"], Args),
    {ok, Conn} = rvi_common:get_json_element(["conn"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status | Rem ] =
	gen_server:call(?SERVER, {rvi, store_certs, [Certs, Conn, LogId]}),
    {ok, [ rvi_common:json_rpc_status(Status) | Rem]};
handle_rpc("authorize_local_message", Args) ->
    {ok, Service} = rvi_common:get_json_element(["service"], Args),
    {ok, Params} = rvi_common:get_json_element(["parameters"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status | Rem ] =
	gen_server:call(?SERVER, { rvi, authorize_local_message,
				   [Service, Params, LogId]}),

    { ok, [ rvi_common:json_rpc_status(Status) | Rem] };


handle_rpc("authorize_remote_message", Args) ->
    {ok, Service} = rvi_common:get_json_element(["service"], Args),
    {ok, Params} = rvi_common:get_json_element(["parameters"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status ]  = gen_server:call(?SERVER, { rvi, authorize_remote_message,
					     [Service, Params, LogId]}),
    { ok, rvi_common:json_rpc_status(Status)};

handle_rpc("filter_by_service", Args) ->
    ?debug("authorize_rpc:handle_rpc(\"filter_by_service\", ~p)~n", [Args]),
    {ok, Services} = rvi_common:get_json_element(["services"], Args),
    {ok, Conn} = rvi_common:get_json_element(["conn"], Args),
    LogId = rvi_common:get_json_log_id(Args),
    [ Status, FilteredServices ] =
	gen_server:call(?SERVER, { rvi, filter_by_service,
				   [Services, Conn, LogId] }),
    {ok, [{status, rvi_common:json_rpc_status(Status)},
	  {services, FilteredServices}]};

handle_rpc(Other, _Args) ->
    ?debug("authorize_rpc:handle_rpc(~p): unknown", [ Other ]),
    { ok, [ { status, rvi_common:json_rpc_status(invalid_command)} ] }.


handle_notification(Other, _Args) ->
    ?debug("authorize_rpc:handle_other(~p): unknown", [ Other ]),
    ok.

%%
%% Genserver implementation
%%
handle_call({rvi, sign_message, [Msg | LogId]}, _, #st{private_key = Key} = State) ->
    Sign = authorize_sig:encode_jwt(Msg, Key),
    log(LogId, "signed", []),
    {reply, [ ok, Sign ], State};
handle_call({rvi, validate_message, [JWT, Conn | LogId]}, _, State) ->
    try  begin Res = authorize_keys:validate_message(JWT, Conn),
	       log(LogId, "validated", []),
	       {reply, [ok, Res], State}
	 end
    catch
	error:_Err ->
	    log(LogId, "validation FAILED", []),
	    {reply, [not_found], State}
    end;
handle_call({rvi, get_authorize_jwt, [_LogId]}, _From, State) ->
    {reply, [ ok, authorize_keys:authorize_jwt() ], State};

handle_call({rvi, get_certificates, [_LogId]}, _From, State) ->
    {reply, [ ok, authorize_keys:get_certificates() ], State};

handle_call({rvi, validate_authorization, [JWT, Conn | [_] = LogId]}, _From, State) ->
    %% The authorize JWT contains the public key used to sign the cert
    ?debug(
       "authorize_rpc:handle_call({rvi, validate_authorization, [_,_,_]})~n",
       []),
    try authorize_sig:decode_jwt(JWT, authorize_keys:provisioning_key()) of
	{_Header, Keys} ->
	    log(LogId, "auth jwt validated", []),
	    KeyStructs = get_json_element(["keys"], Keys, []),
	    authorize_keys:save_keys(KeyStructs, Conn),
	    {reply, [ok], State};
	invalid ->
	    ?warning("Invalid auth JWT from ~p~n", [Conn]),
	    log(LogId, "auth jwt INVALID", []),
	    {reply, [not_found], State}
    catch
	error:_Err ->
	    ?warning("Auth validation exception: ~p~n", [_Err]),
	    {reply, [not_found], State}
    end;

handle_call({rvi, validate_authorization, [JWT, Certs, Conn | [_] = LogId] }, _From, State) ->
    %% The authorize JWT contains the public key used to sign the cert
    ?debug(
       "authorize_rpc:handle_call({rvi, validate_authorization, [_,_,_]})~n",
       []),
    try authorize_sig:decode_jwt(JWT, authorize_keys:provisioning_key()) of
	{_Header, Keys} ->
	    log(LogId, "auth jwt validated", []),
	    KeyStructs = get_json_element(["keys"], Keys, []),
	    ?debug("KeyStructs = ~p~n", [KeyStructs]),
	    authorize_keys:save_keys(KeyStructs, Conn),
	    do_store_certs(Certs, Conn, LogId),
	    {reply, [ok], State};
	invalid ->
	    ?warning("Invalid auth JWT from ~p~n", [Conn]),
	    log(LogId, "auth jwt INVALID", []),
	    {reply, [not_found], State}
    catch
	error:_Err ->
	    ?warning("Auth validation exception: ~p~n", [_Err]),
	    {reply, [not_found], State}
    end;

handle_call({store_certs, [Certs, Conn | LogId]}, _From, State) ->
    do_store_certs(Certs, Conn, LogId),
    {reply, [ok], State};
handle_call({rvi, authorize_local_message, [Service, _Params | LogId] } = R, _From, State) ->
    ?debug("authorize_rpc:handle_call(~p)~n", [R]),
    case authorize_keys:find_cert_by_service(Service) of
	{ok, {ID, _Cert}} ->
	    %% Msg = Params ++ [{<<"certificate">>, Cert}],
	    %% ?debug("authorize_rpc:authorize_local_message~nMsg = ~p~n",
	    %% 	   [authorize_keys:abbrev_payload(Msg)]),
	    %% Sig = authorize_sig:encode_jwt(Msg, Key),
	    log(LogId, "auth msg: Cert=~s", [authorize_keys:abbrev_bin(ID)]),
	    {reply, [ok], State};
	_ ->
	    log(LogId, "NO CERTS for ~s", [Service]),
	    {reply, [ not_found ], State}
    end;

handle_call({rvi, authorize_remote_message, [_Service, Params | LogId]},
	    _From, State) ->
    IP = proplists:get_value(remote_ip, Params),
    Port = proplists:get_value(remote_port, Params),
    Timeout = proplists:get_value(timeout, Params),
    SvcName = proplists:get_value(service_name, Params),
    Parameters = proplists:get_value(parameters, Params),
    ?debug("authorize_rpc:authorize_remote_message(): remote_ip:     ~p~n", [IP]),
    ?debug("authorize_rpc:authorize_remote_message(): remote_port:   ~p~n", [Port]),
    ?debug("authorize_rpc:authorize_remote_message(): timeout:       ~p~n", [Timeout]),
    ?debug("authorize_rpc:authorize_remote_message(): service_name:  ~p~n", [SvcName]),
    ?debug("authorize_rpc:authorize_remote_message(): parameters:    ~p~n", [Parameters]),
    case authorize_keys:validate_service_call(SvcName, {IP, Port}) of
	invalid ->
	    log(LogId, "remote msg REJECTED", []),
	    {reply, [ not_found ], State};
	{ok, CertID} ->
	    ?debug("validated Cert ID=~p", [CertID]),
	    log(LogId, "remote msg allowed: Cert=~s", [CertID]),
	    {reply, [ok], State}
    end;

handle_call({rvi, filter_by_service, [Services, Conn | _LogId]}, _From, State) ->
    Filtered = authorize_keys:filter_by_service(Services, Conn),
    {reply, [ok, Filtered], State};

handle_call({sign, Term}, _From, #st{private_key = Key} = State) ->
    {reply, authorize_sig:encode_jwt(Term, Key), State};

handle_call(public_key, _From, #st{public_key = Key} = State) ->
    {reply, Key, State};

handle_call(public_key_json, _From, #st{public_key = Key} = State) ->
    {reply, authorize_keys:public_key_to_json(Key), State};

handle_call(private_key, _From, #st{private_key = Key} = State) ->
    {reply, Key, State};

handle_call(Other, _From, State) ->
    ?warning("authorize_rpc:handle_call(~p): unknown", [ Other ]),
    { reply, unknown_command, State}.

handle_cast(Other, State) ->
    ?warning("authorize_rpc:handle_cast(~p): unknown", [ Other ]),
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

do_store_certs(Certs, Conn, LogId) ->
    ?debug("Storing ~p certs for conn ~p~n", [length(Certs), Conn]),
    lists:foreach(fun(Cert) ->
			  store_cert(Cert, Conn, LogId)
		  end, Certs).

get_json_element(Path, JSON, Default) ->
    case rvi_common:get_json_element(Path, JSON) of
	{ok, Value} ->
	    Value;
	_ ->
	    Default
    end.

store_cert(Cert, Conn, LogId) ->
    case authorize_sig:decode_jwt(Cert, authorize_keys:provisioning_key()) of
	{_CHeader, CertStruct} ->
	    case authorize_keys:save_cert(CertStruct, Cert, Conn, LogId) of
		ok ->
		    ok;
		{error, Reason} ->
		    ?warning(
		       "Couldn't store certificate from ~p: ~p~n",
		       [Conn, Reason]),
		    ok
	    end;
	invalid ->
	    ?warning("Invalid certificate from ~p~n", [Conn]),
	    ok
    end.

log([ID], Fmt, Args) ->
    rvi_log:log(ID, <<"authorize">>, rvi_log:format(Fmt, Args));
log(_, _, _) ->
    ok.

%% check_msg(Checks, Params) ->
%%     check_msg(Checks, Params, []).

    %% 	    {ok, Timeout1} = rvi_common:get_json_element(["timeout"], Msg),
    %% 	    {ok, SvcName1} = rvi_common:get_json_element(["service_name"], Msg),
    %% 	    {ok, Params1} = rvi_common:get_json_element(["parameters"], Msg),
    %% 	    ?debug("authorize_rpc:authorize_remote_message(): timeout1:      ~p~n", [Timeout1]),
    %% 	    ?debug("authorize_rpc:authorize_remote_message(): service_name1: ~p~n", [SvcName1]),
    %% 	    ?debug("authorize_rpc:authorize_remote_message(): parameters1:   ~p~n", [Params1]),

    %% 	    if Timeout =:= Timeout1 * 1000,
    %% 	       SvcName =:= SvcName1,
    %% 	       Parameters =:= Params1 ->
    %% 		    ?debug("Remote message authorized.~n", []),
    %% 		    {reply, [ ok ], State};
    %% 	       true ->
    %% 		    ?debug("Remote message NOT authorized.~n", []),
    %% 		    {reply, [ not_found ], State}
    %% 	    end
    %% end;

%% check_msg([], _, []) ->
%%     ok;
%% check_msg([{Key, Expect}|T], Msg, Acc) ->
%%     case rvi_common:get_json_element([Key], Msg) of
%% 	{ok, Expect} ->
%% 	    check_msg(T, Msg, Acc);
%% 	_ ->
%% 	    check_msg(T, Msg, [Key|Acc])
%%     end;
%% check_msg([], _, [_|_] = Acc) ->
%%     {error, {mismatch, lists:reverse(Acc)}}.
