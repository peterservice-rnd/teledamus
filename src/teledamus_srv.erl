-module(teledamus_srv).

-behaviour(gen_server).

-include_lib("teledamus_rr.hrl").
-include_lib("teledamus.hrl").

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, get_connection/0, get_connection/1, release_connection/1, release_connection/2]).

-type cnode() :: [{nonempty_string(), pos_integer()}].
-record(state, {nodes :: rr_state(cnode()), opts :: list(), credentials :: {string(), string()}, transport = gen_tcp :: teledamus:transport(), compression = none :: teledamus:compression(), channel_monitor :: atom()}).

%%%===================================================================
%%% API
%%%===================================================================

get_connection() ->
    gen_server:call(?MODULE, get_connection).

get_connection(Timeout) ->
    gen_server:call(?MODULE, get_connection, Timeout).


release_connection(Connection) ->
    gen_server:call(?MODULE, {release_connection, Connection}).

release_connection(Connection, Timeout) ->
    gen_server:call(?MODULE, {release_connection, Connection}, Timeout).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(list()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
    Credentials = {proplists:get_value(username, Args), proplists:get_value(password, Args)},
    ChannelMonitor = proplists:get_value(channel_monitor, Args, undefined),
    Nodes = proplists:get_value(cassandra_nodes, Args),
    Transport = case proplists:get_value(transport, Args, tcp) of
        tcp -> gen_tcp;
        ssl -> ssl
    end,
    Opts = prepare_transport(Transport, Args),
    Init = fun() ->
        #tdm_rr_state{resources = Nodes, rr = Nodes}
    end,
    Compression = proplists:get_value(compression, Args, none),
    tdm_stmt_cache:init(),
    tdm_connection:prepare_ets(),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [#tdm_rr_state{init = Init}, Opts, Credentials, Transport, Compression, ChannelMonitor], []).

prepare_transport(gen_tcp, Args) ->
    proplists:get_value(tcp_opts, Args, []);
prepare_transport(ssl, Args) ->
    ok = application:ensure_started(asn1, permanent),
    ok = application:ensure_started(crypto, permanent),
    ok = application:ensure_started(public_key, permanent),
    ok = application:ensure_started(ssl, permanent),
    proplists:get_value(tcp_opts, Args, []) ++ proplists:get_value(ssl_opts, Args, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([RR, Opts, Credentials, Transport, Compression, ChannelMonitor]) ->
    {ok, #state{nodes = tdm_rr:reinit(RR), opts = Opts, credentials = Credentials, transport = Transport, compression = Compression, channel_monitor = ChannelMonitor}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call(Request, From, State) ->
    #state{nodes = Nodes, opts = Opts, credentials = Credentials, transport = Transport, compression = Compression, channel_monitor = ChannelMonitor} = State,
    case Request of
        get_connection -> % todo: connection pooling
            case tdm_rr:next(Nodes) of
                {error_no_resources, _S} ->
                    throw(error_no_resources);
                {{Host, Port}, NS} ->
                    spawn(fun() ->
                        try
                            case Transport:connect(Host, Port, Opts) of
                                {ok, Socket} ->
%% 									process_flag(trap_exit, true),
                                    {ok, Pid} = tdm_connection:start(Socket, Credentials, Transport, Compression, Host, Port, ChannelMonitor),
                                    DefStream = tdm_connection:get_default_stream(#tdm_connection{pid = Pid}),
                                    Connection = #tdm_connection{pid = Pid, host = Host, port = Port, default_stream = DefStream},
                                    ok = Transport:controlling_process(Socket, Pid),
                                    gen_server:reply(From, Connection);
                                {error, Reason} ->
                                    gen_server:reply(From, {error, Reason})
                            end
                        catch
                            E:EE ->
                                error_logger:error_msg("Connection error: ~p:~p, trace=~p", [E, EE, erlang:get_stacktrace()]),
                                gen_server:reply(From, {error, {E, EE, erlang:get_stacktrace()}})
                        end
                    end),
                    {noreply, State#state{nodes = NS}}
            end;

        {release_connection, Connection} ->
            #tdm_connection{pid = Pid} = Connection,
            case is_process_alive(Pid) of
                true ->
                    Socket = tdm_connection:get_socket(Connection),
                    Transport:close(Socket),
                    {reply, ok, State};
                false ->
                    {reply, {error, connection_is_not_alive}, State}
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(Request, State) ->
    #state{nodes = Nodes} = State,
    %% todo: add public api and/or automatic cluster changes discovery
    case Request of
        {add_node, Host, Port} ->
            {noreply, State#state{nodes = tdm_rr:add(Nodes, {Host, Port})}};
        {remove_node, Host, Port} ->
            {noreply, State#state{nodes = tdm_rr:remove(Nodes, {Host, Port})}};
        reload_nodes ->
            {noreply, State#state{nodes = tdm_rr:reinit(Nodes)}};
        _ ->
            {noreply, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

