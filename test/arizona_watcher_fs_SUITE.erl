-module(arizona_watcher_fs_SUITE).
-include_lib("stdlib/include/assert.hrl").

-define(STATE, #{sup => self()}).

-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    event_created/1,
    event_modified/1,
    event_deleted/1,
    event_renamed/1,
    event_dir_renamed/1,
    event_removed/1,
    event_unrelated/1,
    save_in_place_reloads/1,
    atomic_rename_save_reloads/1,
    stop_shuts_fs_down/1,
    fs_crash_stops_rule/1
]).

%% ============================================================================
%% CT callbacks
%% ============================================================================

all() ->
    [{group, events}, {group, integration}].

groups() ->
    [
        {events, [parallel], [
            event_created,
            event_modified,
            event_deleted,
            event_renamed,
            event_dir_renamed,
            event_removed,
            event_unrelated
        ]},
        {integration, [sequence], [
            save_in_place_reloads,
            atomic_rename_save_reloads,
            stop_shuts_fs_down,
            fs_crash_stops_rule
        ]}
    ].

%% The rule process broadcasts on arizona's pubsub scope, which is a `pg` scope;
%% the arizona application itself is not needed.
init_per_suite(Config) ->
    {ok, Pg} = pg:start(arizona_pubsub),
    [{pg, Pg} | Config].

end_per_suite(Config) ->
    exit(proplists:get_value(pg, Config), kill),
    ok.

init_per_testcase(TC, Config) when
    TC =:= save_in_place_reloads;
    TC =:= atomic_rename_save_reloads;
    TC =:= stop_shuts_fs_down;
    TC =:= fs_crash_stops_rule
->
    Dir = filename:join(
        "/tmp", "arizona_watcher_fs_ct_" ++ integer_to_list(erlang:unique_integer([positive]))
    ),
    ok = file:make_dir(Dir),
    Self = self(),
    {ok, Rule} = arizona_reloader_rule:start_link(Dir, #{
        watcher => arizona_watcher_fs,
        patterns => ["\\.erl$"],
        debounce => 50,
        callback => fun(Files) -> Self ! {changed, Files} end
    }),
    ok = await_watching(Dir),
    [{rule, Rule}, {dir, Dir} | Config];
init_per_testcase(_TC, Config) ->
    Config.

end_per_testcase(_TC, Config) ->
    case proplists:get_value(rule, Config) of
        undefined ->
            ok;
        Rule ->
            case is_process_alive(Rule) of
                true -> ok = gen_server:stop(Rule);
                false -> ok
            end,
            ok = file:del_dir_r(proplists:get_value(dir, Config))
    end.

%% ============================================================================
%% events group tests
%% ============================================================================

event_created(Config) when is_list(Config) ->
    ?assertEqual({ok, ["/d/a.erl"], ?STATE}, fs_event("/d/a.erl", [created])).

event_modified(Config) when is_list(Config) ->
    ?assertEqual({ok, ["/d/a.erl"], ?STATE}, fs_event("/d/a.erl", [modified, closed])).

event_deleted(Config) when is_list(Config) ->
    ?assertEqual({ok, ["/d/a.erl"], ?STATE}, fs_event("/d/a.erl", [deleted])).

%% Atomic-rename saves (vim, `sed -i`, agent file-writers) write a temp file
%% then rename() over the target; inotify reports the MOVED_TO as `renamed`,
%% which must reload like an in-place save.
event_renamed(Config) when is_list(Config) ->
    ?assertEqual({ok, ["/d/a.erl"], ?STATE}, fs_event("/d/a.erl", [renamed])).

%% A directory rename is not a source-file edit.
event_dir_renamed(Config) when is_list(Config) ->
    ?assertEqual({ok, [], ?STATE}, fs_event("/d/sub.erl", [isdir, renamed])).

%% A file moved *out* of the directory (MOVED_FROM) is delete-like: its path is
%% now absent, and a real delete already reports `deleted`.
event_removed(Config) when is_list(Config) ->
    ?assertEqual({ok, [], ?STATE}, fs_event("/d/a.erl", [removed])).

event_unrelated(Config) when is_list(Config) ->
    ?assertEqual({ok, [], ?STATE}, arizona_watcher_fs:handle_info(other, ?STATE)).

%% ============================================================================
%% integration group tests
%% ============================================================================

save_in_place_reloads(Config) when is_list(Config) ->
    File = filename:join(proplists:get_value(dir, Config), "mod.erl"),
    ok = file:write_file(File, ~"-module(mod)."),
    ?assertEqual([File], await_changed()).

atomic_rename_save_reloads(Config) when is_list(Config) ->
    Dir = proplists:get_value(dir, Config),
    Tmp = filename:join(Dir, ".mod.erl.swp"),
    File = filename:join(Dir, "mod.erl"),
    ok = file:write_file(Tmp, ~"-module(mod)."),
    ok = file:rename(Tmp, File),
    ?assertEqual([File], await_changed()).

%% An orderly stop shuts the named `fs` instance down with the rule process.
stop_shuts_fs_down(Config) when is_list(Config) ->
    Rule = proplists:get_value(rule, Config),
    [_ | _] = Before = fs_names(),
    ok = gen_server:stop(Rule),
    ?assertEqual([], [Name || Name <- fs_names(), lists:member(Name, Before)]).

%% The fs supervisor is linked to the rule process, which traps exits: its crash
%% must stop the rule (so the rule's supervisor restarts the watch) rather than
%% leave it up with no watch behind it.
fs_crash_stops_rule(Config) when is_list(Config) ->
    Rule = proplists:get_value(rule, Config),
    [FsSup] = [whereis(Name) || Name <- fs_names(), lists:suffix("sup", atom_to_list(Name))],
    Ref = monitor(process, Rule),
    unlink(Rule),
    exit(FsSup, kill),
    receive
        {'DOWN', Ref, process, Rule, killed} -> ok
    after 1000 -> ct:fail(rule_not_stopped)
    end.

%% ============================================================================
%% Helpers
%% ============================================================================

fs_event(Path, Events) ->
    arizona_watcher_fs:handle_info({self(), {fs, file_event}, {Path, Events}}, ?STATE).

%% `fs` reports nothing until its OS process has set its watches up, which
%% happens after `init/2` returns. Touch a sentinel until a change comes through,
%% then drop it, so a test's own write is never lost to that startup window.
await_watching(Dir) ->
    await_watching(filename:join(Dir, ".ready.erl"), 50).

await_watching(_Sentinel, 0) ->
    ct:fail(watch_never_ready);
await_watching(Sentinel, Tries) ->
    ok = file:write_file(Sentinel, integer_to_binary(Tries)),
    receive
        {changed, _} ->
            ok = file:delete(Sentinel),
            receive
                {changed, _} -> ok
            after 1000 -> ok
            end
    after 100 -> await_watching(Sentinel, Tries - 1)
    end.

%% Waits for the debounced callback; the burst of events one save produces
%% arrives as one list.
await_changed() ->
    receive
        {changed, Files} -> lists:usort(Files)
    after 5000 -> ct:fail(no_change_reported)
    end.

fs_names() ->
    [
        Name
     || Name <- registered(),
        lists:prefix("arizona_watcher_fs_", atom_to_list(Name))
    ].
