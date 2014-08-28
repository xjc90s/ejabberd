%%%----------------------------------------------------------------------
%%% File    : ejabberd_odbc_sup.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : ODBC connections supervisor
%%% Created : 22 Dec 2004 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2014   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_odbc_sup).

-author('alexey@process-one.net').

%% API
-export([start_link/1, init/1, get_pids/1, get_pids_shard/2,
	 get_random_pid/1, get_random_pid_shard/2,
	 transform_options/1]).

-include("ejabberd.hrl").
-include("logger.hrl").

-define(PGSQL_PORT, 5432).

-define(MYSQL_PORT, 3306).

-define(DEFAULT_POOL_SIZE, 10).

-define(DEFAULT_ODBC_START_INTERVAL, 30).

-define(CONNECT_TIMEOUT, 500).

start_link(Host) ->
    supervisor:start_link({local,
			   gen_mod:get_module_proc(Host, ?MODULE)},
			  ?MODULE, [Host]).

init([Host]) ->
    PoolSize = get_pool_size(Host),
    StartInterval = get_start_interval(Host),

    Pool =
	lists:map(fun (I) ->
			  {ejabberd_odbc:get_proc(Host, I),
			   {ejabberd_odbc, start_link,
			    [Host, I, StartInterval * 1000]},
			   transient, 2000, worker, [?MODULE]}
		  end,
		  lists:seq(1, PoolSize)),

    ShardPools =
	lists:map(
	  fun(S) ->
		  lists:map(
		    fun (I) ->
			    {ejabberd_odbc:get_proc(Host, S, I),
			     {ejabberd_odbc, start_link,
			      [Host, S, I, StartInterval * 1000]},
			     transient, 2000, worker, [?MODULE]}
		    end,
		    lists:seq(1, PoolSize))
	  end,
	  lists:seq(1, get_shard_size(Host))),
    {ok,
     {{one_for_one, PoolSize * 10, 1},
      lists:flatten([Pool, ShardPools])}}.


get_start_interval(Host) ->
    ejabberd_config:get_option(
      {odbc_start_interval, Host},
      fun(I) when is_integer(I), I>0 -> I end,
      ?DEFAULT_ODBC_START_INTERVAL).

get_pool_size(Host) ->
    ejabberd_config:get_option(
      {odbc_pool_size, Host},
      fun(I) when is_integer(I), I>0 -> I end,
      ?DEFAULT_POOL_SIZE).

get_shard_size(Host) ->
    length(ejabberd_config:get_option(
	     {shards, Host},
	     fun(S) when is_list(S) -> S end,
	     [])).

get_pids(Host) ->
    [ejabberd_odbc:get_proc(Host, I) ||
	I <- lists:seq(1, get_pool_size(Host))].

get_pids_shard(Host, Key) ->
    [ejabberd_odbc:get_proc(Host, get_shard(Host, Key), I) ||
	I <- lists:seq(1, get_pool_size(Host))].

get_shard(Host, Key) ->
    erlang:phash2(Key, get_shard_size(Host)) + 1.

get_random_pid(Host) ->
    get_random_pid(Host, now()).

get_random_pid(Host, Term) ->
    I = erlang:phash2(Term, get_pool_size(Host)) + 1,
    ejabberd_odbc:get_proc(Host, I).

get_random_pid_shard(Host, Key) ->
    get_random_pid_shard(Host, Key, now()).

get_random_pid_shard(Host, Key, Term) ->
    I = erlang:phash2(Term, get_pool_size(Host)) + 1,
    S = get_shard(Host, Key),
    ejabberd_odbc:get_proc(Host, S, I).


transform_options(Opts) ->
    lists:foldl(fun transform_options/2, [], Opts).

transform_options({odbc_server,
		   {Type, Server, Port, DB, User, Pass}}, Opts) ->
    [{odbc_type, Type},
     {odbc_server, Server},
     {odbc_port, Port},
     {odbc_database, DB},
     {odbc_username, User},
     {odbc_password, Pass}|Opts];
transform_options({odbc_server, {mysql, Server, DB, User, Pass}}, Opts) ->
    transform_options(
      {odbc_server, {mysql, Server, ?MYSQL_PORT, DB, User, Pass}}, Opts);
transform_options({odbc_server, {pgsql, Server, DB, User, Pass}}, Opts) ->
    transform_options(
      {odbc_server, {pgsql, Server, ?PGSQL_PORT, DB, User, Pass}}, Opts);
transform_options(Opt, Opts) ->
    [Opt|Opts].
