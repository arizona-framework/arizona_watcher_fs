-module(arizona_watcher_fs).
-moduledoc """
`arizona_watcher` implementation on the [`fs`](https://hex.pm/packages/fs)
library (inotify on Linux, FSEvents on macOS, the Windows API on Windows).

Add the package to a dev-only rebar3 profile and name it in the arizona
`reloader` env:

```erlang
%% rebar.config
{profiles, [{dev, [{deps, [arizona_watcher_fs]}]}]}.

%% config/dev.config
{arizona, [
    {reloader, #{
        enabled => true,
        watcher => arizona_watcher_fs,
        rules => [#{directory => "src", patterns => [".*\\.erl$"],
                    callback => fun arizona_reloader:reload_erl/1}]
    }}
]}.
```

It takes no options.

## Events

`fs` reports raw events; a path counts as changed on `created`, `modified`,
`deleted`, or `renamed` (the inotify MOVED_TO). The last is what an
atomic-rename save produces -- write a temp file, then `rename()` it over the
target -- which is how vim, `sed -i`, and most editors and agent file-writers
save. Two events are left out: a directory rename (`renamed` with `isdir`) is
not a source-file edit, and a file moved out of the directory (`removed`, the
inotify MOVED_FROM) is delete-like with its path now absent.

## Lifecycle

Each watch is a named `fs` instance (`fs` registers its processes, so the
name is an atom derived from the calling process and the directory) whose
supervisor is linked to the calling rule process, so a crashing watch stops
the rule and its supervisor restarts it. `fs` runs an OS process (`sh` + `inotifywait` on
Linux) with the watched directory as its cwd; `terminate/1` shuts the instance
down and waits for it, so a caller that deletes the watched directory right
after does not race its `getcwd`.

The `fs` application itself is never started: its default env starts a
recursive watcher on the node's working directory. That is why `fs` is a
dependency of this package but not in its `applications`.
""".
-behaviour(arizona_watcher).

%% --------------------------------------------------------------------
%% arizona_watcher callback exports
%% --------------------------------------------------------------------

-export([init/2]).
-export([handle_info/2]).
-export([terminate/1]).

%% --------------------------------------------------------------------
%% Types exports
%% --------------------------------------------------------------------

-export_type([state/0]).

%% --------------------------------------------------------------------
%% Ignore elvis warnings
%% --------------------------------------------------------------------

%% Watch names are derived from a hash of {self, dir} and registered as atoms
%% because `fs` requires named processes.
-elvis([{elvis_style, no_common_caveats_call, disable}]).

%% --------------------------------------------------------------------
%% Types definitions
%% --------------------------------------------------------------------

-nominal state() :: #{sup := pid()}.

%% --------------------------------------------------------------------
%% arizona_watcher Callbacks
%% --------------------------------------------------------------------

-doc "Starts a named `fs` watch on `Dir` and subscribes the calling process.".
-spec init(Dir, Opts) -> {ok, state()} | {error, term()} when
    Dir :: string(),
    Opts :: map().
init(Dir, #{}) ->
    Name = watch_name(Dir),
    maybe
        {ok, Sup} ?= fs:start_link(Name, Dir),
        ok ?= fs:subscribe(Name),
        {ok, #{sup => Sup}}
    end.

-doc "Reports the path of an `fs` file event that is a content change.".
-spec handle_info(Info, State) -> {ok, [string()], State} when
    Info :: term(),
    State :: state().
handle_info({_Pid, {fs, file_event}, {Path, Events}}, State) ->
    case is_content_change(Events) of
        true -> {ok, [Path], State};
        false -> {ok, [], State}
    end;
handle_info(_Info, State) ->
    {ok, [], State}.

-doc "Shuts the `fs` watch down and waits for its OS process.".
-spec terminate(State) -> ok when
    State :: state().
terminate(#{sup := Sup}) ->
    Ref = monitor(process, Sup),
    exit(Sup, shutdown),
    %% No timeout of its own: the rule process's shutdown timeout bounds this
    %% wait, and if it expires the rule is killed and the link takes the watch
    %% down with it. An already-dead supervisor (the rule stopping because the
    %% watch crashed) answers the monitor with `noproc` at once.
    receive
        {'DOWN', Ref, process, Sup, _} -> ok
    end,
    %% port_close sends SIGHUP but the OS process may still be exiting. Give it
    %% a moment so a caller that deletes the watched directory doesn't race with
    %% its getcwd.
    timer:sleep(10).

%% --------------------------------------------------------------------
%% Internal functions
%% --------------------------------------------------------------------

watch_name(Dir) ->
    Hash = erlang:phash2({self(), Dir}),
    list_to_atom("arizona_watcher_fs_" ++ integer_to_list(Hash)).

is_content_change(Events) ->
    lists:member(created, Events) orelse
        lists:member(modified, Events) orelse
        lists:member(deleted, Events) orelse
        is_file_rename(Events).

%% The inotify backend maps an atomic-rename save's MOVED_TO to `renamed`;
%% without it those saves would silently skip hot reload. A `renamed` that is a
%% directory is not a source-file edit.
is_file_rename(Events) ->
    lists:member(renamed, Events) andalso not lists:member(isdir, Events).
