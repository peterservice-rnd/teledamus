%% -*- coding: utf-8 -*-
-module(tdm_cql1_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("teledamus.hrl").

-export([dummy_zip/1, dummy_unzip/1]).

parse_flags_test() ->
    ?assertEqual(<<3>>, tdm_cql1:encode_flags(#tdm_flags{compressing = true, tracing = true})),
    ?assertEqual(<<1>>, tdm_cql1:encode_flags(#tdm_flags{compressing = true, tracing = false})),
    ?assertEqual(<<2>>, tdm_cql1:encode_flags(#tdm_flags{compressing = false, tracing = true})),
    ?assertEqual(#tdm_flags{compressing = true, tracing = true}, tdm_cql1:parse_flags(<<3>>)),
    ?assertEqual(#tdm_flags{compressing = false, tracing = true}, tdm_cql1:parse_flags(<<2>>)),
    ?assertEqual(#tdm_flags{compressing = true, tracing = false}, tdm_cql1:parse_flags(<<1>>)).

parse_header_test() ->
    H = #tdm_header{type = request, version = 1, flags = #tdm_flags{compressing = true, tracing = false}, opcode = 12, stream = 37},
    ?assertEqual(<<0:1,1:7,1:8,37:8,12:8>>, tdm_cql1:encode_frame_header(H)),
    ?assertEqual(<<1:1,1:7,1:8,37:8,12:8>>, tdm_cql1:encode_frame_header(H#tdm_header{type = response, version = 3})),
    ?assertEqual(<<0:1,1:7,3:8,37:8,12:8>>, tdm_cql1:encode_frame_header(H#tdm_header{flags = #tdm_flags{tracing = true, compressing = true}})),
    ?assertEqual(<<0:1,1:7,1:8,-1:8/big-signed-integer,21:8>>, tdm_cql1:encode_frame_header(H#tdm_header{opcode = 21, stream = -1})),
    ?assertEqual(H, tdm_cql1:parse_frame_header(<<0:1,1:7,1:8,37:8,12:8>>)),
    ?assertEqual(H#tdm_header{type = response, version = 3}, tdm_cql1:parse_frame_header(<<1:1,3:7,1:8,37:8,12:8>>)),
    ?assertEqual(H#tdm_header{flags = #tdm_flags{tracing = true, compressing = true}}, tdm_cql1:parse_frame_header(<<0:1,1:7,3:8,37:8,12:8>>)),
    ?assertEqual(H#tdm_header{opcode = 21, stream = -1}, tdm_cql1:parse_frame_header(<<0:1,1:7,1:8,-1:8/big-signed-integer,21:8>>)).


parse_frame_test() ->
    F = #tdm_frame{header = #tdm_header{type = request, version = 1, flags = #tdm_flags{compressing = false, tracing = false}, opcode = 12, stream = 37}, body = <<>>},
    ?assertEqual(<<0:1,1:7,0:8,37:8,12:8,0:32/big-unsigned-integer>>, tdm_cql1:encode_frame(F, none)),
    ?assertEqual(<<0:1,1:7,0:8,37:8,12:8,3:32/big-unsigned-integer,1,2,3>>, tdm_cql1:encode_frame(F#tdm_frame{body = <<1, 2, 3>>}, none)),
    ?assertEqual({F#tdm_frame{length = 0}, <<>>}, tdm_cql1:parse_frame(<<0:1,1:7,0:8,37:8,12:8,0:32/big-unsigned-integer>>, none)),
    ?assertEqual({F#tdm_frame{length = 0}, <<1,2,3>>}, tdm_cql1:parse_frame(<<0:1,1:7,0:8,37:8,12:8,0:32/big-unsigned-integer,1,2,3>>, none)),
    ?assertEqual({F#tdm_frame{length = 3, body= <<1,2,3>>}, <<>>}, tdm_cql1:parse_frame(<<0:1,1:7,0:8,37:8,12:8,3:32/big-unsigned-integer,1,2,3>>, none)),
    ?assertEqual({F#tdm_frame{length = 3, body= <<1,2,3>>}, <<4,5>>}, tdm_cql1:parse_frame(<<0:1,1:7,0:8,37:8,12:8,3:32/big-unsigned-integer,1,2,3,4,5>>, none)).

parse_simple_datatypes_test() ->
    % int
    ?assertEqual({27, <<1,2,3,4,5>>}, tdm_cql1:parse_int(<<27:32/big-signed-integer,1,2,3,4,5>>)),
    ?assertEqual(tdm_cql1:encode_int(27), <<27:32/big-signed-integer>>),

    % short
    ?assertEqual({72, <<1,2,3,4,5>>}, tdm_cql1:parse_short(<<72:16/big-unsigned-integer,1,2,3,4,5>>)),
    ?assertEqual(tdm_cql1:encode_short(72), <<72:16/big-signed-integer>>),

    %	short string
    ?assertEqual({"abcdef", <<1,2,3>>}, tdm_cql1:parse_string(<<6:16/big-unsigned-integer,97,98,99,100,101,102,1,2,3>>)),
    ?assertEqual({"абв", <<1,2,3>>}, tdm_cql1:parse_string(<<6:16/big-unsigned-integer,"абв"/utf8-big,1,2,3>>)),
    ?assertEqual(<<6:16/big-unsigned-integer,97,98,99,100,101,102>>, tdm_cql1:encode_string("abcdef")),
    ?assertEqual(<<6:16/big-unsigned-integer,"абв"/utf8-big>>, tdm_cql1:encode_string("абв")),

    % long string
    ?assertEqual({"abcdef", <<1,2,3>>}, tdm_cql1:parse_long_string(<<6:32/big-signed-integer,97,98,99,100,101,102,1,2,3>>)),
    ?assertEqual({"абв", <<1,2,3>>}, tdm_cql1:parse_long_string(<<6:32/big-signed-integer,"абв"/utf8-big,1,2,3>>)),
    ?assertEqual(<<6:32/big-unsigned-integer,97,98,99,100,101,102>>, tdm_cql1:encode_long_string("abcdef")),
    ?assertEqual(<<6:32/big-unsigned-integer,"абв"/utf8-big>>, tdm_cql1:encode_long_string("абв")),

    % uuid
    ?assertEqual({<<1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16>>, <<17>>}, tdm_cql1:parse_uuid(<<1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17>>)),
    ?assertEqual(<<1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16>>, tdm_cql1:encode_uuid(<<1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16>>)),

    % byte
    ?assertEqual({<<0>>, <<1, 2, 3, 4, 5,6>>}, tdm_cql1:parse_byte(<<0,1,2,3,4,5,6>>)),
    ?assertEqual(<<7>>, tdm_cql1:encode_byte(7)),


    % bytes
    ?assertEqual({<<0,1,2,3,4>>, <<5,6>>}, tdm_cql1:parse_bytes(<<5:32,0,1,2,3,4,5,6>>)),
    ?assertEqual(<<5:32,0,1,2,3,4>>, tdm_cql1:encode_bytes(<<0,1,2,3,4>>)),

    % short bytes
    ?assertEqual({<<0,1,2,3,4>>, <<5,6>>}, tdm_cql1:parse_short_bytes(<<5:16,0,1,2,3,4,5,6>>)),
    ?assertEqual(<<5:16,0,1,2,3,4>>, tdm_cql1:encode_short_bytes(<<0,1,2,3,4>>)),

    % consistency level
    ?assertEqual({any, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<0:16,1,2,3>>)),
    ?assertEqual({one, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<1:16,1,2,3>>)),
    ?assertEqual({two, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<2:16,1,2,3>>)),
    ?assertEqual({three, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<3:16,1,2,3>>)),
    ?assertEqual({quorum, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<4:16,1,2,3>>)),
    ?assertEqual({all, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<5:16,1,2,3>>)),
    ?assertEqual({local_quorum, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<6:16,1,2,3>>)),
    ?assertEqual({each_quorum, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<7:16,1,2,3>>)),
    ?assertEqual({serial, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<8:16,1,2,3>>)),
    ?assertEqual({local_serial, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<9:16,1,2,3>>)),
    ?assertEqual({local_one, <<1,2,3>>}, tdm_cql1:parse_consistency_level(<<10:16,1,2,3>>)),
    ?assertEqual(<<0,0>>, tdm_cql1:encode_consistency_level(any)),
    ?assertEqual(<<0,1>>, tdm_cql1:encode_consistency_level(one)),
    ?assertEqual(<<0,2>>, tdm_cql1:encode_consistency_level(two)),
    ?assertEqual(<<0,3>>, tdm_cql1:encode_consistency_level(three)),
    ?assertEqual(<<0,4>>, tdm_cql1:encode_consistency_level(quorum)),
    ?assertEqual(<<0,5>>, tdm_cql1:encode_consistency_level(all)),
    ?assertEqual(<<0,6>>, tdm_cql1:encode_consistency_level(local_quorum)),
    ?assertEqual(<<0,7>>, tdm_cql1:encode_consistency_level(each_quorum)),
    ?assertEqual(<<0,8>>, tdm_cql1:encode_consistency_level(serial)),
    ?assertEqual(<<0,9>>, tdm_cql1:encode_consistency_level(local_serial)),
    ?assertEqual(<<0,10>>, tdm_cql1:encode_consistency_level(local_one)),
    ok.

parse_complex_datatypes_test() ->
    % string list
    ?assertEqual({["abc","de"], <<1,2,3>>}, tdm_cql1:parse_string_list(<<2:16/big-unsigned-integer,3:16/big-unsigned-integer,97,98,99,2:16/big-unsigned-integer,100,101,1,2,3>>)),
    ?assertEqual(<<0,2,0,3,97,98,99,0,2,100,101>>, tdm_cql1:encode_string_list(["abc", "de"])),
    ?assertEqual({["абв","гд"], <<1,2,3>>}, tdm_cql1:parse_string_list(<<2:16/big-unsigned-integer,0,6,"абв"/utf8-big,0,4,"гд"/utf8-big,1,2,3>>)),
    ?assertEqual(<<0,2,0,6,"абв"/utf8-big,0,4,"гд"/utf8-big>>, tdm_cql1:encode_string_list(["абв", "гд"])),

    % string map
    ?assertEqual({[{"abc", "de"}, {"f", "g"}, {"h", "ijk"}], <<1,2>>}, tdm_cql1:parse_string_map(<<3:16,3:16,97,98,99,2:16,100,101,1:16,102,1:16,103,1:16,104,3:16,105,106,107,1,2>>)),
    ?assertEqual(<<3:16,3:16,97,98,99,2:16,100,101,1:16,102,1:16,103,1:16,104,3:16,105,106,107>>, tdm_cql1:encode_string_map([{"abc", "de"}, {"f", "g"}, {"h", "ijk"}])),

    % string multimap
    ?assertEqual({[{"ab", ["c", "de"]}, {"f", []}], <<1,2>>}, tdm_cql1:parse_string_multimap(<<2:16,2:16,97,98,2:16,1:16,99,2:16,100,101,1:16,102,0:16,1,2>>)),
    ?assertEqual(<<2:16,2:16,97,98,2:16,1:16,99,2:16,100,101,1:16,102,0:16>>, tdm_cql1:encode_string_multimap([{"ab", ["c", "de"]}, {"f", []}])),

    ?assertEqual({{custom, "abc"}, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_CUSTOM:16,3:16,97,98,99,1,2,3>>)),
    ?assertEqual({ascii, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_ASCII:16,1,2,3>>)),
    ?assertEqual({bigint, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_BIGINT:16,1,2,3>>)),
    ?assertEqual({blob, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_BLOB:16,1,2,3>>)),
    ?assertEqual({boolean, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_BOOLEAN:16,1,2,3>>)),
    ?assertEqual({counter, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_COUNTER:16,1,2,3>>)),
    ?assertEqual({decimal, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_DECIMAL:16,1,2,3>>)),
    ?assertEqual({double, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_DOUBLE:16,1,2,3>>)),
    ?assertEqual({float, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_FLOAT:16,1,2,3>>)),
    ?assertEqual({int, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_INT:16,1,2,3>>)),
    ?assertEqual({text, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_TEXT:16,1,2,3>>)),
    ?assertEqual({timestamp, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_TIMESTAMP:16,1,2,3>>)),
    ?assertEqual({uuid, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_UUID:16,1,2,3>>)),
    ?assertEqual({varchar, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_VARCHAR:16,1,2,3>>)),
    ?assertEqual({varint, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_VARINT:16,1,2,3>>)),
    ?assertEqual({timeuuid, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_TIMEUUID:16,1,2,3>>)),
    ?assertEqual({inet, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_INET:16,1,2,3>>)),

    ?assertEqual({{list, int}, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_LIST:16, ?OPT_INT:16, 1,2,3>>)),
    ?assertEqual({{map, boolean, text}, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_MAP:16, ?OPT_BOOLEAN:16, ?OPT_TEXT:16, 1,2,3>>)),
    ?assertEqual({{set, ascii}, <<1,2,3>>}, tdm_cql1:parse_option(<<?OPT_SET:16, ?OPT_ASCII:16, 1,2,3>>)),
    ok.


parse_errors_test() ->
    MkTestCode = fun(Code, Msg, Postfix) ->
        C = tdm_cql1:encode_int(Code),
        M = tdm_cql1:encode_string(Msg),
        B = <<C/binary, M/binary, Postfix/binary>>,
        #tdm_frame{body = B}
    end,
    ?assertEqual(#tdm_error{error_code = ?ERR_SERVER_ERROR, message = "abcdef", type = server_error, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_SERVER_ERROR, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_PROTOCOL_ERROR, message = "abcdef", type = protocol_error, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_PROTOCOL_ERROR, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_BAD_CREDENTIALS, message = "abcdef", type = bad_credentials, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_BAD_CREDENTIALS, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_UNAVAILABLE_EXCEPTION, message = "abcdef", type = unavailable_exception, additional_info = [{consistency_level, any}, {nodes_required, 5}, {nodes_alive, 3}]},
        tdm_cql1:parse_error(MkTestCode(?ERR_UNAVAILABLE_EXCEPTION, "abcdef", <<0:16,5:32,3:32>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_OVERLOADED, message = "abcdef", type = coordinator_node_is_overloaded, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_OVERLOADED, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_IS_BOOTSTRAPING, message = "abcdef", type = coordinator_node_is_bootstrapping, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_IS_BOOTSTRAPING, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_TRUNCATE_ERROR, message = "abcdef", type = truncate_error, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_TRUNCATE_ERROR, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_WRITE_TIMEOUT, message = "abcdef", type = write_timeout, additional_info = [{consistency_level, one}, {nodes_received, 2}, {nodes_required, 5}, {write_type, "abc"}]},
        tdm_cql1:parse_error(MkTestCode(?ERR_WRITE_TIMEOUT, "abcdef", <<1:16,2:32,5:32,3:16,97,98,99>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_READ_TIMEOUT, message = "abcdef", type = read_timeout, additional_info = [{consistency_level, one}, {nodes_received, 2}, {nodes_required, 5}, {data_present, true}]},
        tdm_cql1:parse_error(MkTestCode(?ERR_READ_TIMEOUT, "abcdef", <<1:16,2:32,5:32,3>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_UNATHORIZED, message = "abcdef", type = unathorized, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_UNATHORIZED, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_SYNTAX_ERROR, message = "abcdef", type = syntax_error, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_SYNTAX_ERROR, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_INVALID, message = "abcdef", type = invalid_query, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_INVALID, "abcdef", <<>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_ALREADY_EXISTS, message = "abcdef", type = already_exists, additional_info = [{keyspace, "abc"},{table, "de"}]},
        tdm_cql1:parse_error(MkTestCode(?ERR_ALREADY_EXISTS, "abcdef", <<3:16,97,98,99,2:16,100,101>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_UNPREPARED, message = "abcdef", type = unprepared_query, additional_info = [{query_id, <<0,1,2,3,4,5,6>>}]},
        tdm_cql1:parse_error(MkTestCode(?ERR_UNPREPARED, "abcdef", <<7:16,0,1,2,3,4,5,6>>))),
    ?assertEqual(#tdm_error{error_code = ?ERR_CONFIG_ERROR, message = "abcdef", type = config_error, additional_info = undefined},
        tdm_cql1:parse_error(MkTestCode(?ERR_CONFIG_ERROR, "abcdef", <<>>))).

parse_metadata_test() ->
    NoMetadataHasMorePage = <<6:32/big-signed-integer,2:32/big-signed-integer,3:32/big-signed-integer,0,1,2,3,4>>,
    ?assertEqual({{[[], []], <<0,1,2>>}, <<3,4>>}, tdm_cql1:parse_metadata(NoMetadataHasMorePage)),
    NoMetadataNoPage = <<4:32/big-signed-integer,2:32/big-signed-integer>>,
    ?assertEqual({{[[],[]], undefined}, <<>>}, tdm_cql1:parse_metadata(NoMetadataNoPage)),
    NoGlobalNoPage = <<0:32,2:32,3:16,97,98,99,2:16,100,101,1:16,102,2:16,2:16,98,99,2:16,100,101,1:16,103,4:16, 1,2,3>>,
    ?assertEqual({{[{"abc", "de", "f", bigint}, {"bc", "de", "g", boolean}], undefined}, <<1,2,3>>}, tdm_cql1:parse_metadata(NoGlobalNoPage)),
    GlobalPage = <<3:32,3:32, 3:32,1,2,3, 3:16,97,98,99, 2:16,100,101, 1:16,97,2:16, 2:16,98,99,4:16, 3:16,100,101,102,8:16>>,
    ?assertEqual({{[{"abc", "de", "a", bigint}, {"abc", "de", "bc", boolean}, {"abc", "de", "def", float}], <<1,2,3>>}, <<>>}, tdm_cql1:parse_metadata(GlobalPage)),
    ok.

parse_row_test() ->
    F = #tdm_frame{header = #tdm_header{type = request, version = 1, flags = #tdm_flags{compressing = true, tracing = false}, opcode = 12, stream = 37}, body = <<>>},
    ?assertEqual(ok, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_VOID:32>>})),
    ?assertEqual({keyspace, "abc"}, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_KEYSPACE:32,3:16,97,98,99>>})),
    ?assertEqual({created, "Abc", "Def"}, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_SCHEMA:32,7:16,"CREATED",3:16,"Abc",3:16,"Def">>})),
    ?assertEqual({updated, "Abc", "Def"}, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_SCHEMA:32,7:16,"UPDATED",3:16,"Abc",3:16,"Def">>})),
    ?assertEqual({dropped, "Abc", "Def"}, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_SCHEMA:32,7:16,"DROPPED",3:16,"Abc",3:16,"Def">>})),
    M = <<1:32,3:32, 3:16,"abc", 2:16,"de", 1:16,"a",2:16, 2:16,"bc",4:16, 3:16,"def",1:16>>,
    R = <<3:32, 4:32,1:32,1:32,1:8,4:32,"abcd", 4:32,2:32,1:32,1:8,4:32,"efgh", 4:32,3:32,1:32,0:8,4:32,"klmn">>, %%
    ?assertEqual({[{"abc", "de", "a", bigint}, {"abc", "de", "bc", boolean}, {"abc", "de", "def", ascii}], undefined,
        [[1, true, "abcd"], [2, true, "efgh"], [3, false, "klmn"]]},
        tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_ROWS:32,M/binary,R/binary>>})),
    ?assertEqual({<<1,2,3>>, {[{"abc", "de", "a", bigint}, {"abc", "de", "bc", boolean}, {"abc", "de", "def", ascii}], undefined}, undefined}, tdm_cql1:parse_result(F#tdm_frame{body = <<?RES_PREPARED:32,3:16,1,2,3,M/binary>>})),
    ok.

parse_event_test() ->
    F = #tdm_frame{header = #tdm_header{type = response, version = 1, flags = #tdm_flags{compressing = true, tracing = false}, opcode = 12, stream = 37}, body = <<>>},
    ?assertEqual({topology_change, new_node, "localhost"}, tdm_cql1:parse_event(F#tdm_frame{body = <<15:16,"TOPOLOGY_CHANGE", 8:16,"NEW_NODE", 9:16,"localhost">>})),
    ?assertEqual({topology_change, removed_node, "localhost"}, tdm_cql1:parse_event(F#tdm_frame{body = <<15:16,"TOPOLOGY_CHANGE", 12:16,"REMOVED_NODE", 9:16,"localhost">>})),
    ?assertEqual({status_change, node_up, "localhost"}, tdm_cql1:parse_event(F#tdm_frame{body = <<13:16,"STATUS_CHANGE", 2:16,"UP", 9:16,"localhost">>})),
    ?assertEqual({status_change, node_down, "localhost"}, tdm_cql1:parse_event(F#tdm_frame{body = <<13:16,"STATUS_CHANGE", 4:16,"DOWN", 9:16,"localhost">>})),
    ?assertEqual({schema_change, created, "KS", "Test"}, tdm_cql1:parse_event(F#tdm_frame{body = <<13:16,"SCHEMA_CHANGE", 7:16,"CREATED", 2:16,"KS", 4:16,"Test">>})),
    ?assertEqual({schema_change, updated, "KS", "Test"}, tdm_cql1:parse_event(F#tdm_frame{body = <<13:16,"SCHEMA_CHANGE", 7:16,"UPDATED", 2:16,"KS", 4:16,"Test">>})),
    ?assertEqual({schema_change, dropped, "KS", "Test"}, tdm_cql1:parse_event(F#tdm_frame{body = <<13:16,"SCHEMA_CHANGE", 7:16,"DROPPED", 2:16,"KS", 4:16,"Test">>})),
    ok.


assert_equal_binary(B1, B2) ->
    if
        B1 =:= B2 -> ok;
        true ->
            ?debugFmt("~nExp: ~p~nRes: ~p", [B1, B2]),
            ?assertEqual(B1, B2)
    end.

encode_query_params_test() ->
    ?assertEqual(<<1:16>>, tdm_cql1:encode_query_params(#tdm_query_params{consistency_level = one})),
    ?assertException(_, {unsupported_protocol_feature, paging, cql1}, tdm_cql1:encode_query_params(#tdm_query_params{consistency_level = one, page_size = 12})),
    ?assertException(_, {unsupported_protocol_feature, conditional_update, cql1}, tdm_cql1:encode_query_params(#tdm_query_params{consistency_level = one, serial_consistency = one})),
    ?assertException(_, {unsupported_protocol_feature, skip_metadata, cql1}, tdm_cql1:encode_query_params(#tdm_query_params{consistency_level = one, skip_metadata = true})),
    ?assertException(_, {unsupported_protocol_feature, bind_variables, cql1}, tdm_cql1:encode_query_params(#tdm_query_params{consistency_level = one, bind_values = [{int, 3}]})),
    ok.

encode_query_test() ->
    P = #tdm_query_params{bind_values = [{ascii, "ks_info"}]},
    ?assertException(_, {unsupported_protocol_feature, bind_variables, cql1}, tdm_cql1:encode_query("SELECT * from system.schema_keyspaces WHERE name = ?", P)),
    assert_equal_binary(<<3:16,1,2,3, 1:16, 7:32,"ks_info", 4:16>>, tdm_cql1:encode_query(<<1,2,3>>, P)),
    ok.


dummy_zip(Body) ->
    <<1,2,3,Body/binary>>.

dummy_unzip(<<1,2,3,Body/binary>>) ->
    Body.

compression_test() ->
    Flags = #tdm_flags{compressing = true, tracing = false},
    Header = #tdm_header{type = request, version = 1, flags = Flags, opcode = 12, stream = 37},
    F = #tdm_frame{header = Header, body = <<>>},
    C = {"test", {tdm_cql1_test, dummy_zip, dummy_unzip}, 3},
    ?assertEqual(<<0:1,1:7,1:8,37:8,12:8,0:32>>, tdm_cql1:encode_frame(F, C)),
    ?assertEqual(<<0:1,1:7,1:8,37:8,12:8,7:32,1,2,3,4,5,6,7>>, tdm_cql1:encode_frame(F#tdm_frame{body = <<4,5,6,7>>}, C)),
    ?assertEqual({F#tdm_frame{length = 0, header = Header#tdm_header{flags = Flags#tdm_flags{compressing = false}}}, <<>>}, tdm_cql1:parse_frame(<<0:1,1:7,0:8,37:8,12:8,0:32/big-unsigned-integer>>, C)),
    ?assertEqual({F#tdm_frame{length = 4, header = Header#tdm_header{flags = Flags#tdm_flags{compressing = false}}, body = <<4,5,6,7>>}, <<1,2,3>>}, tdm_cql1:parse_frame(<<0:1,1:7,1:8,37:8,12:8,7:32,1,2,3,4,5,6,7,1,2,3>>, C)),
    ok.