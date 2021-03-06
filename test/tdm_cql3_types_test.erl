%% -*- coding: utf-8 -*-
-module(tdm_cql3_types_test).

-include_lib("eunit/include/eunit.hrl").
-include_lib("teledamus.hrl").

encode_test() ->
    ?assertEqual(<<5:32,1,2,3,4,5>>, tdm_cql3_types:encode({custom, "Abc"}, <<1,2,3,4,5>>)),
    ?assertEqual(<<3:32,97,98,99>>, tdm_cql3_types:encode(ascii, "abc")),
    ?assertEqual(<<8:32, 137:64>>, tdm_cql3_types:encode(bigint, 137)),
    ?assertEqual(<<6:32, 1,2,3,4,5,6>>, tdm_cql3_types:encode(blob, <<1,2,3,4,5,6>>)),
    ?assertEqual(<<1:32,1>>, tdm_cql3_types:encode(boolean, true)),
    ?assertEqual(<<1:32,0>>, tdm_cql3_types:encode(boolean, false)),
    ?assertEqual(<<8:32, 13:64>>, tdm_cql3_types:encode(counter, 13)),
    ?assertEqual(<<6:32, 2:32, 251, 255>>, tdm_cql3_types:encode(decimal, #tdm_decimal{scale = 2, value = -1025})),
    ?assertEqual(<<4:32, 2.5:32/big-float>>, tdm_cql3_types:encode(float, 2.5)),
    ?assertEqual(<<8:32, 3.5:64/big-float>>, tdm_cql3_types:encode(double, 3.5)),
    ?assertEqual(<<4:32, 7:32>>, tdm_cql3_types:encode(int, 7)),
    ?assertEqual(<<6:32, "абв"/big-utf8>>, tdm_cql3_types:encode(text, "абв")),
    ?assertEqual(<<8:32, 137:64>>, tdm_cql3_types:encode(timestamp, 137)),
    ?assertEqual(<<8:32, 1,2,3,4,5,6,7,8>>, tdm_cql3_types:encode(uuid, <<1,2,3,4,5,6,7,8>>)),
    ?assertEqual(<<6:32, "абв"/big-utf8>>, tdm_cql3_types:encode(varchar, "абв")),
    ?assertEqual(<<2:32, (-128):16/big-signed-integer>>, tdm_cql3_types:encode(varint, -128)),
    ?assertEqual(<<8:32, 1,2,3,4,5,6,7,8>>, tdm_cql3_types:encode(timeuuid, <<1,2,3,4,5,6,7,8>>)),
    ?assertEqual(<<4:32, 127,0,0,1>>, tdm_cql3_types:encode(inet, #tdm_inet{ip = {127,0,0,1}})), %% , port = 8080
    ?assertEqual(<<16:32, 127:16,0:16,0:16,1:16,1:16,2:16,3:16,4:16>>, tdm_cql3_types:encode(inet, #tdm_inet{ip = {127,0,0,1,1,2,3,4}})),  % , port = 8080

    ?assertEqual(<<28:32, 2:32, 8:32,12:64, 8:32,13:64>>, tdm_cql3_types:encode({list, bigint}, [12, 13])),
    ?assertEqual(<<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32>>, tdm_cql3_types:encode({list, int}, [1, 3, 5])),
    ?assertEqual(<<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32>>, tdm_cql3_types:encode({set, int}, [1, 3, 5])),
    ?assertEqual(<<30:32, 2:32, 4:32,1:32, 1:32,1, 4:32,3:32, 1:32,0>>, tdm_cql3_types:encode({map, int, boolean}, [{1, true}, {3, false}])),

    ?assertEqual(<<21:32, 4:32,2:32, 1:32,1:8, 4:32,"test" >>, tdm_cql3_types:encode(
        #tdm_udt{keyspace = "KS", name = "Test", fields = [{"fld1", int}, {"fld2", boolean}, {"fld3", ascii}]},
        [{"fld1", 2}, {"fld2", true}, {"fld3", "test"}])
    ),

    ?assertEqual(<<21:32, 4:32,3:32, 1:32,1:8, 4:32,"test">>, tdm_cql3_types:encode({tuple, [int, boolean, ascii]}, [3, true, "test"])),
    ok.

decode_test() ->
    ?assertEqual({<<1,2,3,4,5>>, <<6>>}, tdm_cql3_types:decode({custom, "Abc"}, <<5:32,1,2,3,4,5,6>>)),
    ?assertEqual({"abc", <<>>}, tdm_cql3_types:decode(ascii, <<3:32,97,98,99>>)),
    ?assertEqual({137, <<>>}, tdm_cql3_types:decode(bigint, <<8:32, 137:64>>)),
    ?assertEqual({<<1,2,3,4,5,6>>, <<>>}, tdm_cql3_types:decode(blob, <<6:32,1,2,3,4,5,6>>)),
    ?assertEqual({true, <<>>}, tdm_cql3_types:decode(boolean, <<1:32, 1>>)),
    ?assertEqual({true, <<>>}, tdm_cql3_types:decode(boolean, <<1:32, 7>>)),
    ?assertEqual({false, <<>>}, tdm_cql3_types:decode(boolean, <<1:32, 0>>)),
    ?assertEqual({13, <<>>}, tdm_cql3_types:decode(counter, <<8:32, 13:64>>)),
    ?assertEqual({#tdm_decimal{scale = 2, value = -1025}, <<>>}, tdm_cql3_types:decode(decimal, <<6:32, 2:32, 251, 255>>)),
    ?assertEqual({2.5, <<>>}, tdm_cql3_types:decode(float, <<4:32, 2.5:32/big-float>>)),
    ?assertEqual({3.5, <<>>}, tdm_cql3_types:decode(float, <<8:32, 3.5:64/big-float>>)),
    ?assertEqual({7, <<>>}, tdm_cql3_types:decode(int, <<4:32, 7:32>>)),
    ?assertEqual({"абв", <<>>}, tdm_cql3_types:decode(text, <<6:32, "абв"/big-utf8>>)),
    ?assertEqual({137, <<>>}, tdm_cql3_types:decode(timestamp, <<8:32, 137:64>>)),
    ?assertEqual({<<1,2,3,4,5,6,7,8>>, <<>>}, tdm_cql3_types:decode(uuid, <<8:32, 1,2,3,4,5,6,7,8>>)),
    ?assertEqual({"абв", <<>>}, tdm_cql3_types:decode(varchar, <<6:32, "абв"/big-utf8>>)),
    ?assertEqual({-128, <<>>}, tdm_cql3_types:decode(varint, <<2:32, (-128):16/big-signed-integer>>)),
    ?assertEqual({<<1,2,3,4,5,6,7,8>>, <<>>}, tdm_cql3_types:decode(timeuuid, <<8:32, 1,2,3,4,5,6,7,8>>)),
    ?assertEqual({#tdm_inet{ip = {127,0,0,1}}, <<>>}, tdm_cql3_types:decode(inet, <<4:32, 127,0,0,1>>)),
    ?assertEqual({#tdm_inet{ip = {127,0,0,1,1,2,3,4}}, <<>>}, tdm_cql3_types:decode(inet, <<16:32, 127:16,0:16,0:16,1:16,1:16,2:16,3:16,4:16>>)),
    ?assertEqual({[12, 13], <<>>}, tdm_cql3_types:decode({list, bigint}, <<28:32, 2:32, 8:32,12:64, 8:32,13:64>>)),
    ?assertEqual({[1, 3, 5], <<>>}, tdm_cql3_types:decode({list, int}, <<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32>>)),
    ?assertEqual({[1, 3, 5], <<>>}, tdm_cql3_types:decode({set, int},  <<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32>>)),
    ?assertEqual({[{1, true}, {3, false}], <<>>}, tdm_cql3_types:decode({map, int, boolean}, <<30:32, 2:32, 4:32,1:32, 1:32,1, 4:32,3:32, 1:32,0>>)),

    ?assertEqual({[{"fld1", 2}, {"fld2", true}, {"fld3", "test"}], <<>>}, tdm_cql3_types:decode(#tdm_udt{keyspace = "KS", name = "Test", fields = [{"fld1", int}, {"fld2", boolean}, {"fld3", ascii}]}, <<21:32, 4:32,2:32, 1:32,1:8, 4:32,"test">>)),
    ?assertEqual({[3, true, "test"], <<>>}, tdm_cql3_types:decode({tuple, [int, boolean, ascii]}, <<21:32, 4:32,3:32, 1:32,1:8, 4:32,"test">>)),
    ok.

helpers_test() ->
    ?assertEqual({{float, 2.5}, <<3,5>>}, tdm_cql3_types:decode_t(float, <<4:32, 2.5:32/big-float,3,5>>)),
    ?assertEqual({{{list, int}, [1, 3, 5]}, <<3,2,1>>}, tdm_cql3_types:decode_t({list, int}, <<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32, 3,2,1>>)),

    ?assertEqual(2.5, tdm_cql3_types:decode_v(float, <<4:32, 2.5:32/big-float,3,5>>)),
    ?assertEqual([1, 3, 5], tdm_cql3_types:decode_v({list, int}, <<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32, 3,2,1>>)),

    ?assertEqual({float, 2.5}, tdm_cql3_types:decode_tv(float, <<4:32, 2.5:32/big-float,3,5>>)),
    ?assertEqual({{list, int}, [1, 3, 5]}, tdm_cql3_types:decode_tv({list, int}, <<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32, 3,2,1>>)),

    ?assertEqual(<<4:32, 2.5:32/big-float>>, tdm_cql3_types:encode_t({float, 2.5})),
    ?assertEqual(<<28:32, 3:32, 4:32,1:32, 4:32,3:32, 4:32,5:32>>, tdm_cql3_types:encode_t({{list, int}, [1, 3, 5]})),

    ?assertEqual(3.5, tdm_cql3_types:erase_type({float, 3.5})),
    ?assertEqual([3.5, 2.3], tdm_cql3_types:erase_type({{list, float}, [3.5, 2.3]})),
    ok.