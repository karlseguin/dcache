A simple, fast and process-free cache. Or, a Dumb Cache.

# Overview
The cache is broken into a configurable number of ETS tables (called segments). The segment for a given key is `:erlang.phash2(key, NUMBER_OF_SEGMENT)` and all operations (get, put, del, ttl, ...) are directed to the correct segment.

Expired values are only removed from the cache when `get` is called on them.

While a maximum cache size must be configured, the size limit is enforced on the segment. That is, given 10 segments and a max size of 10_000, the maximum size of each segment will be 1000. When a segment is full, the segment is erased.

The cache spawns no additional process. 

`put` *may* result in an O(N) operation when a segment is (N = MAX_SIZE / NUMBER_OF_SEGMENT). Creating a cache with more segment reduces this cost. Specifically, the O(N) operation is a call to :ets.delete_all_objects/1.

The cache will never grow beyond the configured MAX_SIZE.

Your keys might hash to only 1 or a few segments. This would negatively impact performance. However, this would likely require a very unfortunate set of keys (e.g. integers with a fixed gaps between them).

## Usage 1
The preferred usage, which offers better performance, is to use the `define/3` macro:

```
defmodule MyApp.Cache do
  require DCache

  DCache.define(Users, 100_000)
  DCache.define(Products, 1_000_000, segment: 100)
end
```

And then call the following on application start:

```
MyApp.Cache.Users.setup()
MyApp.Cache.Products.setup()
```

You can then use the caching methods on the created module, e.g:

```
MyApp.Cache.Users.get(KEY)
```

## Usage 2
Alternatively, you can create the cache at runtime. Note that this will require 1 extra ETS lookup for every call, as well as requiring 1 extra ETS table to be allocated.

```
DCache.setup(:users, 100_000)
DCache.setup(:products, 1_000_000, segments: 100)
```

Which you can then use as:

```
DCache.get(:users, KEY)
```

## Functions
Regardless of which of the above two approaches you use, the same functionality is available:

### get/1 & get/2
```
Cache.Users.get(key)
# OR
DCache.get(:users, key)
```

Returns the value from the cache. Returns `nil` if the key isn't found or if the value is expired.

### del/1 & del/2
```
Cache.Users.del(key)
# OR
DCache.del(:users, key)
```

Deletes the value from the cache. Does nothing if the key isn't found. The return value is currently always true.

### ttl/1 & ttl/2
```
Cache.Users.ttl(key)
# OR
DCache.ttl(:users, key)
```

Returns the unix time, in seconds, when the value will be considered expired. Returns `nil` if the key isn't found. This can return a value which is less than now.

### put/3 & put/4
```
Cache.Users.put(key, value, ttl)
# OR
DCache.put(:users, key, value, ttl)
```

Stores the value in the cache. The ttl is given in seconds relative to now (e.g. 300 to have the value expire in 5 minutes).


### fetch/2, fetch/3 & fetch/4
```
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
```
Cache.Users.size()
# OR
DCache.size(:users)
```

Returns the total number of items in the cache, including expired items. This is an O(N) operation where N is the number of segments (which will typically be small).
