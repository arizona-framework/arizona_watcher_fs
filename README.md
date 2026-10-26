# arizona_watcher_fs

[`fs`](https://hex.pm/packages/fs)-based file watcher for
[Arizona](https://github.com/arizona-framework/arizona)'s dev-mode hot reload (inotify on Linux,
FSEvents on macOS, the Windows API on Windows).

Arizona defines the watcher as a behaviour, `arizona_watcher`, and ships no implementation, so a
production build never carries a file-system dependency. `arizona_watcher_fs` is the
implementation you add for development.

## Installation

Add it to a dev-only profile in your `rebar.config`, so a production release never pulls it (or
`fs`) in:

```erlang
{profiles, [
    {dev, [
        {deps, [arizona_watcher_fs]}
    ]}
]}.
```

It needs Arizona 0.4 or newer, the first release with the `arizona_watcher` behaviour. On Linux,
`fs` needs `inotifywait` (the `inotify-tools` package).

## Usage

Name it as the reloader's `watcher` in your dev config:

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

A path counts as changed on `created`, `modified`, `deleted`, or `renamed` -- the last being the
atomic-rename save (write a temp file, `rename()` it over the target) that vim, `sed -i`, and most
editors use. A directory rename and a file moved out of the watched directory are ignored.
Patterns, debouncing, and the callback are Arizona's (`arizona_reloader_rule`), so they behave the
same whatever watcher runs underneath.

### Dev releases

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

## 🚧 Status

arizona_watcher_fs is in `0.x`, like Arizona itself. The core is functional and covered by tests,
but the API may change between minor versions. Pin an exact version in your deps if you need
stability across upgrades.

## Sponsors

arizona_watcher_fs is open source and maintained on personal time. If you or your company find it
useful, consider [sponsoring](https://github.com/sponsors/williamthome).

I also accept coffees ☕

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/williamthome)

<a href="https://github.com/sponsors/williamthome">
  <img
    src="https://raw.githubusercontent.com/williamthome/williamthome/sponsorkit/sponsors.svg"
    alt="Sponsors"
  />
</a>

## Contributing

Contributions are welcome! Run `rebar3 precommit` before opening a pull request: it checks
formatting, runs xref, hank, dialyzer, and the docs build, and runs the tests with a 100% coverage
gate. The integration tests watch a real directory, so on Linux they need `inotifywait`.

## License

Copyright (c) 2026 [William Fank Thomé](https://github.com/williamthome)

arizona_watcher_fs is open-source under the Apache 2.0 License on
[GitHub](https://github.com/arizona-framework/arizona_watcher_fs).

See [LICENSE.md](https://github.com/arizona-framework/arizona_watcher_fs/blob/main/LICENSE.md) for more information.
