-module(connection).

-behaviour(gen_server).

-include_lib("native_protocol.hrl").

-type socket() :: gen_tcp:socket() | ssl:sslsocket().

%% API
-export([start/6, prepare_ets/0]).
-export([options/2, query/4, prepare_query/3, execute_query/4, batch_query/3, subscribe_events/3, get_socket/1, from_cache/2, to_cache/3, query/5, prepare_query/4, batch_query/4,
         new_stream/2, release_stream/2, send_frame/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_STREAM_ID, 0).
-define(DEF_STREAM_ETS, default_streams).

-record(state, {transport = gen_tcp :: tcp | ssl, socket :: socket(), buffer = <<>>:: binary(), caller :: pid(), compression = none :: none | lz4 | snappy, streams :: dict(), host :: list(), port :: pos_integer()}).  %% stmts_cache::dict(binary(), list()), streams:: dict(pos_integer(), stream())


%%%===================================================================
%%% API
%%%===================================================================

send_frame(Pid, Frame) ->
	gen_server:cast(Pid, {send_frame, Frame}).

new_stream(#connection{pid = Pid}, Timeout) ->
  gen_server:call(Pid, new_stream, Timeout).

release_stream(S = #stream{connection = #connection{pid = Pid}}, Timeout) ->
  gen_server:call(Pid, {release_stream, S}, Timeout).


options(#connection{pid = Pid}, Timeout) ->
  Stream = get_default_stream(Pid),
  stream:options(Stream, Timeout).

query(#connection{pid = Pid}, Query, Params, Timeout) ->
	Stream = get_default_stream(Pid),
	stream:query(Stream, Query, Params, Timeout).

query(#connection{pid = Pid}, Query, Params, Timeout, UseCache) ->
	Stream = get_default_stream(Pid),
	stream:query(Stream, Query, Params, Timeout, UseCache).

prepare_query(#connection{pid = Pid}, Query, Timeout) ->
	Stream = get_default_stream(Pid),
  stream:prepare_query(Stream, Query, Timeout).

prepare_query(#connection{pid = Pid}, Query, Timeout, UseCache) ->
	Stream = get_default_stream(Pid),
	stream:prepare_query(Stream, Query, Timeout, UseCache).

execute_query(#connection{pid = Pid}, ID, Params, Timeout) ->
	Stream = get_default_stream(Pid),
  stream:execute_query(Stream, ID, Params, Timeout).

batch_query(#connection{pid = Pid}, Batch, Timeout) ->
	Stream = get_default_stream(Pid),
  stream:batch_query(Stream, Batch, Timeout).

batch_query(#connection{pid = Pid}, Batch, Timeout, UseCache) ->
	Stream = get_default_stream(Pid),
	stream:batch_query(Stream, Batch, Timeout, UseCache).

subscribe_events(#connection{pid = Pid}, EventTypes, Timeout) ->
	Stream = get_default_stream(Pid),
	stream:subscribe_events(Stream, EventTypes, Timeout).

get_socket(#connection{pid = Pid})->
  gen_server:call(Pid, get_socket).

from_cache(#connection{host = Host, port = Port}, Query) ->
  stmt_cache:from_cache({Host, Port, Query}).

to_cache(#connection{host = Host, port = Port}, Query, PreparedStmtId) ->
  stmt_cache:to_cache({Host, Port, Query}, PreparedStmtId).

prepare_ets() ->
	case ets:info(?DEF_STREAM_ETS) of
		undefined -> ets:new(?DEF_STREAM_ETS, [named_table, set, public, {write_concurrency, false}, {read_concurrency, true}]);
		_ -> ?DEF_STREAM_ETS
	end.


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start(Socket, Credentials, Transport, Compression, Host, Port) ->
  gen_server:start(?MODULE, [Socket, Credentials, Transport, Compression, Host, Port], []).

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
init([Socket, Credentials, Transport, Compression, Host, Port]) ->
  RR = case startup(Socket, Credentials, Transport, Compression) of
    ok ->
			try
        set_active(Socket, Transport),
        Connection = #connection{pid = self(), host = Host, port = Port},
				{ok, StreamId} = stream:start(Connection, ?DEFAULT_STREAM_ID, Compression),
				monitor(process, StreamId),
				DefStream = #stream{connection = Connection, stream_id = ?DEFAULT_STREAM_ID, stream_pid = StreamId},
				ets:insert(?DEF_STREAM_ETS, {self(), DefStream}),
        {ok, #state{socket = Socket, transport = Transport, compression = Compression, streams = dict:append(?DEFAULT_STREAM_ID, DefStream, dict:new())}}
		  catch
				E: EE ->
				  {stop, {error, E, EE}}
		  end;
    {error, Reason} ->
      {stop, Reason};
    R ->
      {stop, {unknown_error, R}}
  end,
  RR.

%% update_state(StreamId, From, State) ->
%%   if
%%     is_integer(StreamId) andalso StreamId > 0 ->
%%       {noreply, State}.
%% ;
%%     true ->
%%       {noreply, State#state{caller = From}}
%%   end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) -> {reply, Reply, State} | {reply, Reply, State, Timeout} | {noreply, State} | {noreply, State, Timeout} | {stop, Reason, Reply, State} | {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(Request, _From, State = #state{socket = Socket, transport = _Transport, compression = Compression, streams = Streams, host = Host, port = Port}) ->
  case Request of
    new_stream ->
      case find_next_stream_id(Streams) of
        no_streams_available ->
          {reply, {error, no_streams_available}, State};
        StreamId ->
          Connection = #connection{pid = self(), host = Host, port = Port},
          case stream:start(Connection, StreamId, Compression) of
            {ok, StreamPid} ->
              Stream = #stream{connection = Connection, stream_pid = StreamPid, stream_id = StreamId},
              {reply, Stream, State#state{streams = dict:append(StreamId, Stream, Streams)}};
            {error, X} ->
              {reply, {error, X}, State}
          end
      end;

    {release_stream, #stream{stream_id = Id}} ->
      %% todo: close something?
      {reply, ok, State#state{streams = dict:erase(Id, Streams)}};

    get_socket ->
      {reply, State#state.socket, Socket};

		_ ->
			error_logger:error_msg("Unknown request ~p~n", [Request]),
			{reply, {error, unknown_request}, State#state{caller = undefined}}
	end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(Request, State = #state{transport = Transport, socket = Socket}) ->
	case Request of
		{send_frame, Frame} ->
			Transport:send(Socket, Frame),
			{noreply, State};

		_ ->
			error_logger:error_msg("Unknown request ~p~n", [Request]),
			{noreply, State#state{caller = undefined}}
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
handle_info({tcp, Socket, Data}, #state{socket = Socket, transport = _Transport, buffer = Buffer, compression = Compression} = State) ->
  case native_parser:parse_frame(<<Buffer/binary, Data/binary>>, Compression) of
    {undefined, NewBuffer} ->
%%       set_active(Socket, Transport),
      {noreply, State#state{buffer = NewBuffer}};
    {Frame, NewBuffer} ->
      handle_frame(Frame, State#state{buffer = NewBuffer})
  end;

handle_info({ssl, Socket, Data}, #state{socket = Socket, buffer = Buffer, compression = Compression} = State) ->
  case native_parser:parse_frame(<<Buffer/binary, Data/binary>>, Compression) of
    {undefined, NewBuffer} ->
      {noreply, State#state{buffer = NewBuffer}};
    {Frame, NewBuffer} ->
      handle_frame(Frame, State#state{buffer = NewBuffer})
  end;

handle_info({tcp_closed, _Socket}, State) ->
  error_logger:error_msg("TCP connection closed~n"),
  {stop, tcp_closed, State};

handle_info({ssl_closed, _Socket}, State) ->
  error_logger:error_msg("SSL connection closed~n"),
  {stop, ssl_closed, State};

handle_info({tcp_error, _Socket, Reason}, State) ->
  error_logger:error_msg("TCP error [~p]~n", [Reason]),
  {stop, {tcp_error, Reason}, State};

handle_info({ssl_error, _Socket, Reason}, State) ->
  error_logger:error_msg("SSL error [~p]~n", [Reason]),
  {stop, {tcp_error, Reason}, State};

handle_info({'Down', From, Reason}, State) ->  %% todo
	error_logger:error_msg("Child killed ~p: ~p, state=~p", [From, Reason, State]),
	case From =:= get_default_stream(self()) of
		true -> {stop, {default_stream_death, Reason}, State};
		_ -> {noreply, State}
	end;

handle_info(Info, State) ->
  error_logger:warning_msg("Unhandled info: ~p~n", [Info]),
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
terminate(_Reason, #state{socket = Socket, transport = Transport}) ->
	ets:delete(?DEF_STREAM_ETS, self()),
  Transport:close(Socket).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.





%%%===================================================================
%%% Internal functions
%%%===================================================================


send(Socket, Transport, Compression, Frame) ->
  F = native_parser:encode_frame(Frame, Compression),
  Transport:send(Socket, F).


set_active(Socket, Transport) ->
  case Transport of
    gen_tcp -> inet:setopts(Socket, [{active, true}]);
    Transport -> Transport:setopts(Socket, [{active, true}])
  end.


handle_frame(Frame = #frame{header = Header}, State = #state{streams = Streams}) ->
%%   set_active(State#state.socket, Transport),
	StreamId = Header#header.stream,
	case dict:is_key(StreamId, Streams) of
		true ->
			[Stream] = dict:fetch(StreamId, Streams),
			stream:handle_frame(Stream#stream.stream_pid, Frame);
		false ->
			Stream = get_default_stream(self()),
			stream:handle_frame(Stream#stream.stream_pid, Frame)
	end,
	{noreply, State}.

startup_opts(Compression) ->
  CQL = [{<<"CQL_VERSION">>,  ?CQL_VERSION}],
  case Compression of
    none ->
      CQL;
    {Name, _, _} ->
      N = list_to_binary(Name),
      [{<<"COMPRESSION", N/binary>>} | CQL];
    _ ->
      throw({unsupported_compression_type, Compression})
  end.


startup(Socket, Credentials, Transport, Compression) ->
  case send(Socket, Transport, Compression, #frame{header = #header{opcode = ?OPC_STARTUP, type = request}, body = native_parser:encode_string_map(startup_opts(Compression))}) of
    ok ->
      {Frame, _R} = read_frame(Socket, Transport, Compression),
      case (Frame#frame.header)#header.opcode of
        ?OPC_ERROR ->
          Error = native_parser:parse_error(Frame),
          error_logger:error_msg("CQL error ~p~n", [Error]),
          {error, Error};
        ?OPC_AUTHENTICATE ->
          {Authenticator, _Rest} = native_parser:parse_string(Frame#frame.body),
          authenticate(Socket, Authenticator, Credentials, Transport, Compression);
        ?OPC_READY ->
          ok;
        _ ->
          {error, unknown_response_code}
      end;
    Error ->
      {error, Error}
  end.

read_frame(Socket, Transport, Compression) ->
  {ok, Data} = Transport:recv(Socket, 8),
  <<_Header:4/binary, Length:32/big-unsigned-integer>> = Data,
  {ok, Body} = if
                 Length =/= 0 ->
                   Transport:recv(Socket, Length);
                 true ->
                   {ok, <<>>}
               end,
  F = <<Data/binary,Body/binary>>,
  native_parser:parse_frame(F, Compression).


encode_plain_credentials(User, Password) when is_list(User) ->
  encode_plain_credentials(list_to_binary(User), Password);
encode_plain_credentials(User, Password) when is_list(Password) ->
  encode_plain_credentials(User, list_to_binary(Password));
encode_plain_credentials(User, Password) when is_binary(User), is_binary(Password)->
  native_parser:encode_bytes(<<0,User/binary,0,Password/binary>>).


authenticate(Socket, Authenticator, Credentials, Transport, Compression) ->
  %% todo: pluggable authentification
  {User, Password} = Credentials,
  case send(Socket, Transport, Compression, #frame{header = #header{opcode = ?OPC_AUTH_RESPONSE, type = request}, body = encode_plain_credentials(User, Password)}) of
    ok ->
      {Frame, _R} = read_frame(Socket, Transport, Compression),
      case (Frame#frame.header)#header.opcode of
        ?OPC_ERROR ->
          Error = native_parser:parse_error(Frame),
          error_logger:error_msg("Authentication error [~p]: ~p~n", [Authenticator, Error]),
          {error, Error};
        ?OPC_AUTH_CHALLENGE ->
          error_logger:error_msg("Unsupported authentication message~n"),
          {error, authentification_error};
        ?OPC_AUTH_SUCCESS ->
          ok;
        _ ->
          {error, unknown_response_code}
      end;
    Error ->
      {error, Error}
  end.


find_next_stream_id(Streams) ->
  find_next_stream_id(1, Streams).

find_next_stream_id(128, _Streams) ->
  no_streams_available;
find_next_stream_id(Id, Streams) ->
  case dict:is_key(Id, Streams) of
    false ->
      Id;
    true ->
      find_next_stream_id(Id + 1, Streams)
  end.

get_default_stream(Pid) ->
	[{_, Stream}] = ets:lookup(?DEF_STREAM_ETS, Pid),
	Stream.
