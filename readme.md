A simple and fast cache. Or, a Dumb Cache.

# Overview
The cache is broken into a configurable number of ETS tables (called segments, defaults to 100). The segment for a given key is `:erlang.phash2(key, NUMBER_OF_SEGMENT)` and all operations (get, put, del, expires, ...) are directed to the segment.

Expired values are only removed from the cache when `get` is called on them.

While a maximum cache size must be configured, the size limit is enforced on the segment. That is, given 10 segments and a max size of 10_000, the maximum size of each segment will be 1000. When a segment is full, the segment is erased.

When new values are inserted into a segment (e.g. via `put` or `fetch`), the size of the segment is checked. If necessary, the segment is purged. The purging behavior is customizable.

Your keys might hash to only 1 or a few segments. This would negatively impact performance. However, this would likely require a very unfortunate set of keys (e.g. integers with a fixed gaps between them).

Single file with no dependencies. Copy and paste it into your project.

## Usage 1
The preferred usage, which offers better performance, is to use the `define/3` macro:

```elixir
defmodule MyApp.Cache do
  require DCache

  DCache.define(Users, 100_000)
  DCache.define(Products, 1_000_000, segment: 100)
end
```

And then call the following on application start:

```elixir
MyApp.Cache.Users.setup()
MyApp.Cache.Products.setup()
```

You can then use the caching methods on the created module, e.g:

```elixir
MyApp.Cache.Users.get(KEY)
```

## Usage 2
Alternatively, you can create the cache at runtime. Note that this will require 1 extra ETS lookup for every call, as well as requiring 1 extra ETS table to be allocated.

```elixir
DCache.setup(:users, 100_000)
DCache.setup(:products, 1_000_000, segments: 100)
```

Which you can then use as:

```elixir
DCache.get(:users, KEY)
```

## Functions
Regardless of which of the above two approaches you use, the same functionality is available:

### get/1 & get/2
```elixir
Cache.Users.get(key)
# OR
DCache.get(:users, key)
```

Returns the value from the cache. Returns `nil` if the key isn't found or if the value is expired.

### del/1 & del/2
```elixir
Cache.Users.del(key)
# OR
DCache.del(:users, key)
```

Deletes the value from the cache. Does nothing if the key isn't found. Always returns `:ok`. Use the lower level `take/1` or `take/2` if you need to delete the key and know whether the key existed.

### take/1 & take/2
```elixir
Cache.Users.take(key)
# OR
DCache.take(:users, key)
```

Deletes and returns the value from the cache

### ttl/1 & ttl/2
```elixir
Cache.Users.ttl(key)
# OR
DCache.ttl(:users, key)
```

Returns the unix time, in seconds, when the value will be considered expired. Returns `nil` if the key isn't found. This can return a value which is less than now.

### put/3 & put/4
```elixir
Cache.Users.put(key, value, ttl)
# OR
DCache.put(:users, key, value, ttl)
```

Stores the value in the cache. The ttl is given in seconds relative to now (e.g. 300 to have the value expire in 5 minutes).


### fetch/2, fetch/3 & fetch/4
```elixir
Cache.Users.fetch(key, fun)
# OR
DCache.fetch(:users, key, fun)
# OR
Cache.Users.fetch(key, fun, ttl)
# OR
DCache.fetch(:users, key, fun, ttl)
```

Returns the value from the cache. If the key is not found, or expired, fun/1 will be called (receiving the key as an argument).

The provided `fun/1` should return one of:
* `{:ok, value}` - to put `value` into the cache with the `ttl` that was provided to `fetch`. `{:ok, value}` will be returned from `fetch`.
* `{:ok, value, ttl}` - to put `value` into the cache with the specified `ttl`.  `{:ok, value}` will be returned from `fetch`.
* `{:skip, value`} - does not place `value` in the cache, but still returns `value` from `fetch`
* `{:error, anything}` - does not place value in the cache and return `{:error, anything}` from fetch.


### fetch!/2, fetch!/3 & fetch!/4

Same as `fetch/2`, `fetch/3` & `fetch/4`, but unwraps `{:ok, value}` into `value` and `{:error, err}` into `raise err`.


### size/0 & size/1
```elixir
Cache.Users.size()
# OR
DCache.size(:users)
```

Returns the total number of items in the cache, including expired items. This is an O(N) operation where N is the number of segments (which will typically be small).

### clear/0 & clear/1
```elixir
Cache.Users.clear()
# OR
DCache.clear(:users)
```

Clears the cache. This blocks all other operations on the cache on a per-segment level, so it should be used sparingly.

## Option
Both ways of creating a cache, using the `define/3` macro or calling `DCache.setup/3` takes a keyword list with optional parameters.

* `:segments` - The number of segments to create. Each segment is 1 ets table. The default depends on the caches configured `max` size. For caches with a max size => 10_000, the segment defaults to 100.

* `:purger` - The purger to use. Defaults to `:default`, but can also be `:no_spawn`, `:blocking` or a custom function. See the following section for more details on purgers.

## Custom Purgers
Whenever a segment needs to grow, the size of the segment is compared against the maximum allowed segment size. If necessary, the segment is purged. This purging strategy is customizable.

The default purger spawns a process and removes all expired values from the segment. If no expired keys exist, the purger will randomly remove keys from the cache. If this also fails, the purger will fallback to using `:ets.delete_all_object/1`, which is blocking. Only 1 purger per segment is allowed to run at a time (a sentinel value within the segment is used.)

As an alternative, the `purger: :no_spawn` option can be specified when creating the cache. This behaves exactly like the default purger, but will not spawn a new process. Instead the purge operation will run as part of the the `put` or `fetch` operation that caused the insert, blocking it. Like the default purger, a sentinel value is used to ensure only 1 purger will execute per segment.

The `purger: :blocking` option simply uses `:ets.delete_all_objects/1` on the segment. This blocks all operations on the segment (including gets), but is much faster. Using `purger: :blocking` when segments are very small is a reasonable option.

Finally, a custom purger can be specified:

```elixir
DCache.define(Users, 100_000, purger: &MyApp.Cache.purge_users/1)
# or
DCache.setup(:users, 100_000, purger: &MyApp.Cache.purge_users/1)
```

The purger receives the ETS name of the segment that is full.
