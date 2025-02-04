%% -*- mode: erlang; indent-tabs-mode: nil -*-
%% Copyright (c) 2008-2024 Robert Virding
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%% File    : lfe_io.erl
%% Author  : Robert Virding
%% Purpose : Some basic i/o functions for Lisp Flavoured Erlang.
%%
%% The io functions have been split into the following modules:
%% lfe_io        - basic read and write functions
%% lfe_io_write  - basic write functions
%% lfe_io_pretty - basic print functions
%% lfe_io_format - formatted output

-module(lfe_io).

-export([get_line/0,get_line/1,get_line/2,collect_line/2]).
-export([parse_file/1,parse_file/2,read_file/1,read_file/2]).
-export([read/0,read/1,read/2,read_line/0,read_line/1,read_line/2]).
-export([read_string/1]).
-export([scan_sexpr/2,scan_sexpr/3]).
-export([print/1,print/2,print1/1,print1/2]).
-export([prettyprint/1,prettyprint/2,
         prettyprint1/1,prettyprint1/2,prettyprint1/3,prettyprint1/4]).
-export([format/2,format/3,fwrite/2,fwrite/3,
         format1/2,fwrite1/2]).

%% -compile(export_all).

-include("lfe.hrl").

%% get_line() -> Data | {error,Error} | eof.
%% get_line(Prompt) -> Data | {error,Error} | eof.
%% get_line(IoDevice, Prompt) -> Data | {error,Error} | eof.
%%  Reads a line from the standard input (IoDevice), prompting it with
%%  Prompt. It saves the input in history.

get_line() ->
    get_line(standard_io, '').

get_line(Prompt) ->
    get_line(standard_io, Prompt).

get_line(IoDevice, Prompt) ->
    io:request(IoDevice, {get_until,unicode,Prompt,lfe_io,collect_line,[]}).

%% collect_line(OldStack, Data) -> {done,Result,Rest} | {more,NewStack}.

collect_line(Stack, Data) ->
    case io_lib:collect_line(start, Data, unicode, ignored) of
        {stop,Result,Rest} ->
            {done,lists:reverse(Stack, Result),Rest};
        MoreStack ->
            {more,MoreStack ++ Stack}
    end.

%% parse_file(FileName|Fd[, Line]) -> {ok,[{Sexpr,Line}]} | {error,Error}.
%%  Parse a file returning the raw sexprs (as it should be) and line
%%  numbers of start of each sexpr. Handle errors consistently.

parse_file(Name) -> parse_file(Name, 1).

parse_file(Name, Line) ->
    with_token_file(Name,
                    fun (Ts, LastLine) -> parse_tokens(Ts, LastLine, []) end,
                    Line).

%% parse_tokens(Tokens, LastLine, Sexprs) ->
%%     {ok, [{Sexpr,Line}]} | {error, Error}.

parse_tokens([_|_]=Ts0, LastLine, Ss) ->
    case lfe_parse:sexpr(Ts0) of
        {ok,L,S,Ts1} -> parse_tokens(Ts1, LastLine, [{S,L}|Ss]);
        {more,Cont} ->
            %% Need more tokens but there are none, so call again to
            %% generate an error message.
            {error,E,_} = lfe_parse:sexpr(Cont, {eof,LastLine}),
            {error,E};
        {error,E,_} -> {error,E}
    end;
parse_tokens([], _, Ss) -> {ok,lists:reverse(Ss)}.

%% read_file(FileName|Fd[, Line]) -> {ok,[Sexpr]} | {error,Error}.
%%  Read a file returning the raw sexprs (as it should be). Handle
%%  errors consistently.

read_file(Name) -> read_file(Name, 1).

read_file(Name, Line) ->
    with_token_file(Name,
                    fun (Ts, LastLine) -> read_tokens(Ts, LastLine, []) end,
                    Line).

%% read_tokens(Tokens, LastLine, Sexprs) -> {ok,[Sexpr]} | {error, Error}.

read_tokens([_|_]=Ts0, LastLine, Ss) ->
    case lfe_parse:sexpr(Ts0) of
        {ok,_,S,Ts1} -> read_tokens(Ts1, LastLine, [S|Ss]);
        {more,Cont} ->
            %% Need more tokens but there are none, so call again to
            %% generate an error message.
            {error,E,_} = lfe_parse:sexpr(Cont, {eof,LastLine}),
            {error,E};
        {error,E,_} -> {error,E}
    end;
read_tokens([], _, Ss) -> {ok,lists:reverse(Ss)}.

%% with_token_file(FileName|Fd, DoFunc, Line)
%%  Open the file, scan all LFE tokens and apply DoFunc on them. Note
%%  that a new file starts at line 1.

with_token_file(Fd, Do, Line) when is_pid(Fd) ->
    with_token_file_fd(Fd, Do, Line);
with_token_file(Name, Do, _Line) ->
    case file:open(Name, [read]) of
        {ok,Fd} ->
            with_token_file_fd(Fd, Do, 1);      %Start at line 1
        {error,Error} -> {error,{none,file,Error}}
    end.

with_token_file_fd(Fd, Do, Line) ->             %Called with a file descriptor
    Ret = case io:request(Fd, {get_until,unicode,'',lfe_scan,tokens,[Line]}) of
              {ok,Ts,LastLine} -> Do(Ts, LastLine);
              {error,Error,_} -> {error,Error}
          end,
    file:close(Fd),                             %Close the file
    Ret.                                        % and return value

%% read() -> {ok,Sexpr} | {error,Error} | eof.
%% read(Prompt) -> {ok,Sexpr} | {error,Error} | eof.
%% read(IoDevice, Prompt) -> {ok,Sexpr} | {error,Error} | eof.
%%  A simple read function. It is not line oriented and stops as soon
%%  as it has consumed enough.

read() -> read(standard_io, '').
read(Prompt) -> read(standard_io, Prompt).
read(Io, Prompt) ->
    case io:request(Io, {get_until,unicode,Prompt,?MODULE,scan_sexpr,[1]}) of
        {ok,Sexpr,_} -> {ok,Sexpr};
        {error,E} -> {error,{1,io,E}};
        {error,Error,_} -> {error,Error};
        {eof,_} -> eof
    end.

%% read_line() -> {ok,Sexpr} | {error,Error} | eof.
%% read_line(Prompt) -> {ok,Sexpr} | {error,Error} | eof.
%% read_line(IoDevice, Prompt) -> {ok,Sexpr} | {error,Error} | eof.
%%  A simple read function. It is line oriented and reads whole lines
%%  until it has consumed enough characters. Left-over characters in
%%  the last line are discarded. We use lfe_io:get_line so we are
%%  certain to save the input history, which makes it nice for the
%%  repl.

read_line() -> read_line(standard_io, '').
read_line(Prompt) -> read_line(standard_io, Prompt).
read_line(Io, Prompt) ->
    %% We input lines and call scan_sexpr directly ourself.
    read_line_1(Io, Prompt, [], 1).

read_line_1(Io, P, C0, L0) ->
    case lfe_io:get_line(Io, P) of
        {error,Error} -> {error,{L0,io,Error}};
        Cs0 ->
            case scan_sexpr(C0, Cs0, L0) of
                {done,{ok,Ret,_L1},_Cs1} -> {ok,Ret};
                {done,{error,Error,_},_Cs1} -> {error,Error};
                {done,{eof,_},_} -> eof;
                {more,C1} ->
                    read_line_1(Io, P, C1, L0)
            end
    end.

%% scan_sexpr(Continuation, Chars) ->
%% scan_sexpr(Continuation, Chars, Line) ->
%%     {done,Ret,Rest} | {more,Continuation}.
%%  This function is a re-entrant call which scans tokens from the
%%  input and parses a sexpr. If there are enough characters then it
%%  returns {done,...} else {cont,Cont} if it needs more characters.
%%  This is continued until a sexpr has been scanned.

scan_sexpr([], Cs) ->
    scan_sexpr({[],[]}, Cs, 1).

scan_sexpr([], Cs, L) ->
    scan_sexpr({[],[]}, Cs, L);
scan_sexpr({Sc,Pc}, Cs, L) ->
    scan_sexpr_1(Sc, Pc, Cs, L).

scan_sexpr_1(Sc0, Pc0, Cs0, L0) ->
    case lfe_scan:token(Sc0, Cs0, L0) of
        {done,{error,_,_},_}=Error -> Error;
        {done,{ok,T,L1},Cs1} ->
            %% We have a token, now check if we have a sexpr.
            case lfe_parse:sexpr(Pc0, [T]) of
                {ok,L2,Sexpr,_} ->
                    {done,{ok,Sexpr,L2},Cs1};
                {error,Error,_} ->
                    {done,{error,Error,Cs1},Cs1};
                {more,Pc1} ->                   %Need more tokens
                    scan_sexpr_1([], Pc1, Cs1, L1)
            end;
        {done,{eof,_},_}=Eof -> Eof;
        {more,Sc1} ->
            {more,{Sc1,Pc0}}
    end.

%% read_string(String) -> {ok,[Sexpr]} | {error,Error}.
%%  Read a string.

read_string(Cs) ->
    case lfe_scan:string(Cs, 1) of
        {ok,Ts,L} ->
           read_tokens(Ts, L, []);
        {error,E,_} -> {error,E}
    end.

%% print([IoDevice], Sexpr) -> ok.
%% print1(Sexpr) -> [char()].
%% print1(Sexpr, Depth) -> [char()].
%%  A simple print function. Does not pretty-print but stops at Depth.

print(S) -> print(standard_io, S).
print(Io, S) -> io:put_chars(Io, print1(S)).

print1(S) -> print1(S, -1).                     %All the way
print1(S, D) -> lfe_io_write:term(S, D).

%% prettyprint([IoDevice], Sexpr) -> ok.
%% prettyprint1(Sexpr, Depth, Indentation, LineLength) -> [char()].
%%  External interface to the prettyprint functions. We need to handle
%%  unicode characters here.

prettyprint(S) -> prettyprint(standard_io, S).
prettyprint(Io, S) ->
    Pp = prettyprint1(S, -1),
    Pb = unicode:characters_to_binary(Pp),
    file:write(Io, Pb).

prettyprint1(S) -> lfe_io_pretty:term(S).
prettyprint1(S, D) -> lfe_io_pretty:term(S, D, 0, 80).
prettyprint1(S, D, I) -> lfe_io_pretty:term(S, D, I, 80).
prettyprint1(S, D, I, L) -> lfe_io_pretty:term(S, D, I, L).

%% format([IoDevice,] Format, Args) -> ok.
%% fwrite([IoDevice,] Format, Args) -> ok.
%% format1(Format, Args) -> [char()].
%% fwrite1(Format, Args) -> [char()].
%%  External interface to the formated output functions.

format(F, As) -> format(standard_io, F, As).
format(Io, F, As) -> io:put_chars(Io, format1(F, As)).

format1(F, As) -> fwrite1(F, As).

fwrite(F, As) -> fwrite(standard_io, F, As).
fwrite(Io, F, As) -> io:put_chars(Io, fwrite1(F, As)).

fwrite1(F, As) ->
    case catch lfe_io_format:fwrite1(F, As) of
        {'EXIT',_} ->                           %Something went wrong
            erlang:error(badarg, [F,As]);       %Signal from here
        Result -> Result
    end.
