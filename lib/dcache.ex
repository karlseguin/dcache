defmodule DCache do
	@doc """
	Creates a module to wrap cache operations. This is the preferred way to
	create a cache as it performs better.

			defmodule App.Cache do
				require DCache
				DCache.define(Users, 100_000)  # creates an App.Cache.Users module
			end

	opts:
		cache: Module
			The name of the module to create. This will be nested within the calling module

		max: integer
			The maximum number of items to hold in the cache

		opts:
			segments: integer
				The number of segments to create (defaults to 100, 10, 3 or 1) depending on `max`

			purger: symbol | function
				The purger to use, defaults to `:fast`
				Supported values:
					`:fast`, `:fast_no_spawn`, `:expired`,`:expired_no_spawn`,
					`:blocking`, `:none` or a custom function
	"""
	defmacro define(cache, max, opts \\ []) do
		quote location: :keep do
			defmodule unquote(cache) do
				@config DCache.Impl.config(unquote(cache), unquote(max), unquote(opts))

				def setup(), do: DCache.Impl.setup(@config)
				def clear(), do: DCache.Impl.clear(@config)
				def destroy(), do: DCache.Impl.destroy(@config)
				def get(key), do: DCache.Impl.get(key, @config)
				def del(key), do: DCache.Impl.del(key, @config)
				def ttl(key), do: DCache.Impl.ttl(key, @config)
				def take(key), do: DCache.Impl.take(key, @config)
				def entry(key), do: DCache.Impl.entry(key, @config)
				def put(key, value, ttl), do: DCache.Impl.put(key, value, ttl, @config)
				def fetch(key, fun, ttl \\ nil), do: DCache.Impl.fetch(key, fun, ttl, @config)
				def fetch!(key, fun, ttl \\ nil), do: DCache.Impl.fetch!(key, fun, ttl, @config)
				def size(), do: DCache.Impl.size(@config)
				def each_segments(fun), do: DCache.Impl.each_segments(fun, @config)
				def reduce_segments(acc, fun), do: DCache.Impl.reduce_segments(acc, fun, @config)
			end
		end
	end

	@doc """
	Creates the cache
	opts:
		cache: atom
			The name of the cache

		max: integer
			The maximum number of items to hold in the cache

		opts:
			segments: integer
				The number of segments to create (defaults to 100)
	"""
	def setup(cache, max, opts \\ []) do
		config = DCache.Impl.config(cache, max, opts)
		:ets.new(cache, [:set, :public, :named_table, read_concurrency: true])
		:ets.insert(cache, {:config, config})
		DCache.Impl.setup(config)
	end

	@doc """
	Clears the cache. While the cache is being cleared, concurrent activity is
	severely limited.
	"""
	def clear(cache), do: DCache.Impl.clear(get_config(cache))

	@doc """
	Destroys the cache. Any call to the cache once destroy is called will raise
	an ArgumentError.
	"""
	def destroy(cache) do
		DCache.Impl.destroy(get_config(cache))
		:ets.delete(cache)
	end

	@doc """
	Gets the entry from the cache, or nil if not found. The entry will be returned
	even if it has expired. The entry is an internal representation that can change.
	You can use `DCache.Entry.key/1`, `DCache.Entry.value/1` and `DCache.Entry.ttl/1`
	to extract the key, value and ttl from an entry
	"""
	def entry(cache, key), do: DCache.Impl.entry(key, get_config(cache))

	@doc """
	Gets the value from the cache, returning nil if not found or expired
	"""
	def get(cache, key), do: DCache.Impl.get(key, get_config(cache))

	@doc """
	Deletes the value from the cache, safe to call even if the key is not in the cache
	"""
	def del(cache, key), do: DCache.Impl.del(key, get_config(cache))

	@doc """
	Returns the time in second until the value expires. `nil` if the key isn't
	found. Can return a negative value if the item has expired but has not
	been purged yet
	"""
	def ttl(cache, key), do: DCache.Impl.ttl(key, get_config(cache))

	@doc """
	Deletes and removes the value from the cache. Returns `nil` if not found.
	Returns {:ok, {key, value, expires}} if found
	"""
	def take(cache, key), do: DCache.Impl.take(key, get_config(cache))


	@doc """
	Puts the value in the cache. TTL is a relative time in second.
	For example, 300 would mean that the value would expire in
	5 minutes
	"""
	def put(cache, key, value, ttl), do: DCache.Impl.put(key, value, ttl, get_config(cache))

	@doc """
	Gets the value from the cache. Executes `fun/1` if the value is not found.
	`fun/1` receives the cache key being looked up and should return one of:
		* `{:ok, value}`
		* `{:ok, value, ttl}`
		* `{:skip, value}`
		* `{:error, term}`
	"""
	def fetch(cache, key, fun, ttl \\ nil), do: DCache.Impl.fetch(key, fun, ttl, get_config(cache))

	@doc """
	Same as fetch, but unwraps the returned value or raises on error.
	"""
	def fetch!(cache, key, fun, ttl \\ nil), do: DCache.Impl.fetch!(key, fun, ttl, get_config(cache))

	@doc """
	Returns the total number of items in the cache, including expired
	items. This is O(N) over the number of segments
	"""
	def size(cache), do: DCache.Impl.size(get_config(cache))

	@doc """
	Reduces each segment name. `fun` will receive the segment name (which is the name
	of an ETS table) plus the accumulator
	"""
	def reduce_segments(cache, acc, fun), do: DCache.Impl.reduce_segments(acc, fun, get_config(cache))

	@doc """
	Iterates each segment name. `fun` will receive the segment name.
	"""
	def each_segments(cache, fun), do: DCache.Impl.each_segments(fun, get_config(cache))

	defp get_config(cache) do
		[{_, config}] = :ets.lookup(cache, :config)
		config
	end

	defmodule Impl do
		@moduledoc false

		def config(cache, max, opts) do
			segment_count = Keyword.get_lazy(opts, :segments, fn ->
				cond do
					max >= 10_000 -> 100
					max >= 100 -> 10
					max >= 10 -> 3
					true -> 1
				end
			end)

			segments = Enum.map(0..(segment_count)-1, fn i ->
				String.to_atom("#{cache}#{i}")
			end)

			purger = Keyword.get(opts, :purger, :fast)
			{List.to_tuple(segments), trunc(max / segment_count), purger}
		end

		def setup({segments, _max_per_segment, _purger}) do
			do_reduce_segments(segments, nil, fn segment, _->
				:ets.new(segment, [
					:set,
					:public,
					:named_table,
					read_concurrency: true,
					write_concurrency: true,
					decentralized_counters: false,
				])
			end)
			:ok
		end

		def clear({segments, _max_per_segment, _purger}) do
			do_reduce_segments(segments, nil, fn segment, _ ->
				:ets.delete_all_objects(segment)
			end)
		end

		def destroy({segments, _max_per_segment, _purger}) do
			do_reduce_segments(segments, nil, fn segment, _ ->
				:ets.delete(segment)
			end)
		end

		def get(key, {segments, _max_per_segment, _purger}) do
			key
			|> segment_for_key(segments)
			|> get_from_segment(key)
		end

		defp get_from_segment(segment, key) do
			with {:ok, {_key, value, expires}} <- entry_for_segment(segment, key),
			     true <- expires > :erlang.monotonic_time(:second)
			do
				{:ok, value}
			else
				nil -> nil
				false ->
					:ets.delete(segment, key)
					nil
			end
		end

		def entry(key, {segments, _max_per_segment, _purger}) do
			key
			|> segment_for_key(segments)
			|> entry_for_segment(key)
		end

		defp entry_for_segment(segment, key) do
			case :ets.lookup(segment, key) do
				[entry] -> {:ok, entry}
				[] -> nil
			end
		end

		def put(key, value, ttl, {segments, max_per_segment, purger}) do
			key
			|> segment_for_key(segments)
			|> put_in_segment(key, value, ttl, max_per_segment, purger)
		end

		defp put_in_segment(segment, key, value, ttl, max_per_segment, purger) do
			expires = :erlang.monotonic_time(:second) + ttl
			entry = {key, value, expires}
			case :ets.insert_new(segment, entry) do
				false -> :ets.insert(segment, entry) # just relace, didn't grow
				true ->
					if :ets.info(segment, :size) > max_per_segment do
						case purger do
							:fast ->
								if lock_purging(segment) do
									spawn fn -> purge_fast(segment, max_per_segment) end
								end
							:fast_no_spawn ->
								if lock_purging(segment) do
									purge_fast(segment, max_per_segment)
								end
							:expired ->
								if lock_purging(segment) do
									spawn fn -> purge_segment(segment, max_per_segment) end
								end
							:expired_no_spawn ->
								if lock_purging(segment) do
									purge_segment(segment, max_per_segment)
								end
							:blocking ->
								:ets.delete_all_objects(segment)
								:ets.insert_new(segment, entry) # re-insert this one we just inserted
							:none -> :ok
							fun -> fun.(segment)
						end
					end
			end
			:ok
		end

		def del(key, {segments, _max_per_segment, _purger}) do
			segment = segment_for_key(key, segments)
			:ets.delete(segment, key)
			:ok
		end

		def ttl(key, {segments, _max_per_segment, _purger}) do
			entry = key
			|> segment_for_key(segments)
			|> entry_for_segment(key)

			case entry do
				{:ok, entry} -> DCache.Entry.ttl(entry)
				nil -> nil
			end
		end

		def take(key, {segments, _max_per_segment, _purger}) do
			segment = segment_for_key(key, segments)
			case :ets.take(segment, key) do
				[] -> nil
				[item] -> {:ok, item}
			end
		end

		def fetch(key, fun, ttl, {segments, max_per_segment, purger}) do
			segment = segment_for_key(key, segments)
			case get_from_segment(segment, key) do
				nil ->
					case fun.(key) do
						{:ok, value} = ok -> put_in_segment(segment, key, value, ttl, max_per_segment, purger); ok
						{:ok, value, ttl} -> put_in_segment(segment, key, value, ttl, max_per_segment, purger); {:ok, value}
						{:error, _} = err -> err
						{:skip, value} -> value
					end
				found -> found
			end
		end

		def fetch!(key, fun, ttl, config) do
			case fetch(key, fun, ttl, config) do
				{:ok, value} -> value
				{:error, err} -> raise err
				whatever -> whatever
			end
		end

		defp segment_for_key(key, segments) do
			hash = :erlang.phash2(key, tuple_size(segments))
			elem(segments, hash)
		end

		def size({segments, _max_per_segment, _purger}) do
			do_reduce_segments(segments, 0, fn segment, size ->
				size + :ets.info(segment, :size)
			end)
		end

		def reduce_segments(acc, fun, {segments, _max_per_segment, _purger}) do
			do_reduce_segments(segments, acc, fun)
		end

		# many internal calls have a `segments` instead of a whole config
		defp do_reduce_segments(segments, acc, fun) do
			Enum.reduce(0..tuple_size(segments)-1, acc, fn i, acc ->
				fun.(elem(segments, i), acc)
			end)
		end

		def each_segments(fun, {segments, _max_per_segment, _purger}) do
			do_each_segments(segments, fun)
		end

		def do_each_segments(segments, fun) do
			do_reduce_segments(segments, nil, fn segment, _ -> fun.(segment) end)
			:ok
		end

		defp lock_purging(segment) do
			:ets.insert_new(segment, {{:dcache, :purging}, nil, 99999999999})
		end

		# really small, just lock it and delete it
		defp purge_segment(segment, max_per_segment) when max_per_segment < 100 do
			:ets.delete_all_objects(segment)
		end

		defp purge_segment(segment, max_per_segment) do
			now = :erlang.monotonic_time(:second)
			:ets.safe_fixtable(segment, true)

			# First try to purge expired slots
			# If we don't purge anything, purge "random" slots
			with 0 <- purge_slots_expired(segment, 0, now, 0)
			do
				purge_iterator(segment, max_per_segment)
			end
		after
			:ets.safe_fixtable(segment, false)
			:ets.delete(segment, {:dcache, :purging})
		end

		# Purges expired items
		defp purge_slots_expired(segment, slot, now, purged) do
			case :ets.slot(segment, slot) do
				:'$end_of_table' -> purged
				entries ->
					purged =
						Enum.reduce(entries, purged, fn {key, _, expires}, purged ->
							case expires < now do
								false -> purged
								true -> :ets.delete(segment, key); purged + 1
							end
						end)
					purge_slots_expired(segment, slot + 1, now, purged)
			end
		end

		defp purge_fast(segment, max_per_segment) do
			:ets.safe_fixtable(segment, true)
			purge_iterator(segment, max_per_segment)
		after
			:ets.safe_fixtable(segment, false)
			:ets.delete(segment, {:dcache, :purging})
		end

		defp purge_iterator(segment, max_per_segment) do
			max_to_purge = max_per_segment * 0.05
			max_to_purge = cond do
				max_to_purge > 1000 -> 1000
				max_to_purge < 10 -> 10
				true -> max_to_purge
			end
			purge_iterator(segment, :ets.first(segment), 0, max_to_purge)
		end

		defp purge_iterator(segment, {:dcache, :purging} = key, purged, max_to_purge) do
			purge_iterator(segment, :ets.next(segment, key), purged, max_to_purge)
		end
		# we've purged the maximum we've been told to
		defp purge_iterator(_segment, _key, max_to_purge, max_to_purge), do: max_to_purge
		defp purge_iterator(_segment, :'$end_of_table', purged, _max_to_purge), do: purged
		defp purge_iterator(segment, key, purged, max_to_purge) do
			:ets.delete(segment, key)
			purge_iterator(segment, :ets.next(segment, key), purged + 1, max_to_purge)
		end
	end

	defmodule Entry do
		@moduledoc """
		Some cache functions return the internal structure of a key=>value pair
		stored within the cache. Future versionsof DCache can change this internal
		structure. This module provides functions to extract the data from this
		structure so that libraries do not need to know about the structure or worry
		about future changes.
		"""

		@doc "
		Extracts the key from the entry. Returns nil if the entry is nil
		"
		def key(nil), do: nil
		def key({key, _value, _expiry}), do: key

		@doc "
		Extracts the value from the entry. Returns nil if the entry is nil.
		"
		def value(nil), do: nil
		def value({_key, value, _expiry}), do: value

		@doc "
		Extracts the ttl in seconds from the entry. Returns nil if the entry is nil.
		The returned value will be negative for already expired entries.
		"
		def ttl(nil), do: nil
		def ttl(entry), do: expiry(entry) - :erlang.monotonic_time(:second)

		@doc "
		Extracts the :erlang.monotonic_time(:second) when the entry will expire.
		Returns nil if the entry is nil. This value will be in the past for already
		expired entries.
		"
		def expiry(nil), do: nil
		def expiry({_key, _value, expiry}), do: expiry
	end
end
