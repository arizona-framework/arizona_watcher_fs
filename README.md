# arizona_watcher_fs

The file watcher for [Arizona](https://github.com/arizona-framework/arizona)'s dev-mode hot
reload, built on the [`fs`](https://hex.pm/packages/fs) library (inotify on Linux, FSEvents on
macOS, the Windows API on Windows).

Arizona defines the watcher as a behaviour, `arizona_watcher`, and ships no implementation, so a
production build never carries a file-system dependency. This package is the implementation you
add for development.

## Setup

Add it to a dev-only profile, so a production release never pulls it (or `fs`) in:

```erlang
%% rebar.config
{profiles, [
    {dev, [
        {deps, [arizona_watcher_fs]}
    ]}
]}.
```

Then name it as the reloader's `watcher`:

```erlang
%% config/dev.config
[
    {arizona, [
        {reloader, #{
            enabled => true,
            watcher => arizona_watcher_fs,
            rules => [
                #{directory => "src", patterns => [".*\\.erl$"],
                  callback => fun arizona_reloader:reload_erl/1},
                #{directory => "priv/static", patterns => [".*\\.css$"],
                  callback => fun arizona_reloader:reload_css/1}
            ]
        }}
    ]}
].
```

and run `rebar3 as dev shell --config config/dev.config`. Arizona refuses to boot with rules but
no `watcher`, or with a `watcher` that is not on the code path, and says which dependency or key
is missing.

On Linux, `fs` needs `inotifywait` (the `inotify-tools` package).

`fs` is a dependency of this package but deliberately not in its `applications`: starting the
`fs` application runs its default watcher on the whole working directory. `rebar3 shell` puts
every dependency on the code path, so nothing more is needed there. A dev **release** only bundles
applications something lists, so add both to the dev profile's relx release, loaded and not
started:

```erlang
{profiles, [
    {dev, [
        {deps, [arizona_watcher_fs]},
        {relx, [{release, {my_app, "0.1.0"}, [my_app, {arizona_watcher_fs, load}, {fs, load}]}]}
    ]}
]}.
```

## What counts as a change

A path is reported on `created`, `modified`, `deleted`, or `renamed` -- the last being the
atomic-rename save (write a temp file, `rename()` it over the target) that vim, `sed -i`, and most
editors use. A directory rename and a file moved out of the watched directory are ignored.
Patterns, debouncing, and the callback are Arizona's (`arizona_reloader_rule`), so they behave the
same whatever watcher runs underneath.

## License

Apache-2.0, see [LICENSE.md](LICENSE.md).
