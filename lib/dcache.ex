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
				The number of segments to create (defaults to 100)
	"""
	defmacro define(cache, max, opts \\ []) do
		quote location: :keep do
			defmodule unquote(cache) do
				@config DCache.Impl.config(unquote(cache), unquote(max), unquote(opts))

				def setup(), do: DCache.Impl.setup(@config)
				def get(key), do: DCache.Impl.get(key, @config)
				def del(key), do: DCache.Impl.del(key, @config)
				def take(key), do: DCache.Impl.take(key, @config)
				def put(key, value, ttl), do: DCache.Impl.put(key, value, ttl, @config)
				def expires(key), do: DCache.Impl.expires(key, @config)
				def fetch(key, fun, ttl \\ nil), do: DCache.Impl.fetch(key, fun, ttl, @config)
				def fetch!(key, fun, ttl \\ nil), do: DCache.Impl.fetch!(key, fun, ttl, @config)
				def size(), do: DCache.Impl.size(@config)
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
	Gets the value from the cache, returning nil if not found or expired
	"""
	def get(cache, key), do: DCache.Impl.get(key, get_config(cache))

	@doc """
	Deletes the value from the cache, safe to call even if the key is not in the cache
	"""
	def del(cache, key), do: DCache.Impl.del(key, get_config(cache))

	@doc """
	Deletes and removes the value from the cache. Returns `nil` if not found.
	Returns {:ok, {key, value, expires}} if found
	"""
	def take(cache, key), do: DCache.Impl.take(key, get_config(cache))


	@doc """
	Gets the unix time in seconds when the value will be considered expired.
	Rrturns `nil` if the value is not found. The return value can
	be in the past
	"""
	def expires(cache, key), do: DCache.Impl.expires(key, get_config(cache))

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

	defp get_config(cache) do
		[{_, config}] = :ets.lookup(cache, :config)
		config
	end

	defmodule Impl do
		@moduledoc false

		def config(cache, max, opts) do
			purger = Keyword.get(opts, :purger, :blocking)
			segment_count = Keyword.get(opts, :segments, 100)
			segments = Enum.map(0..(segment_count)-1, fn i ->
				String.to_atom("#{cache}#{i}")
			end)
			{List.to_tuple(segments), trunc(max / segment_count), purger}
		end

		def setup({segments, _max_per_segment, _purger}) do
			reduce_segments(segments, nil, fn segment, _->
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

		def get(key, {segments, _max_per_segment, _purger}) do
			key
			|> segment_for_key(segments)
			|> get_from_segment(key)
		end

		defp get_from_segment(segment, key) do
			with [{_key, value, expires}] <- :ets.lookup(segment, key),
			     true <- expires > :erlang.system_time(:second)
			do
				{:ok, value}
			else
				[] -> nil
				false ->
					:ets.delete(segment, key)
					nil
			end
		end

		def put(key, value, ttl, {segments, max_per_segment, purger}) do
			key
			|> segment_for_key(segments)
			|> put_in_segment(key, value, ttl, max_per_segment, purger)
		end

		defp put_in_segment(segment, key, value, ttl, max_per_segment, purger) do
			expires = :erlang.system_time(:second) + ttl
			entry = {key, value, expires}
			case :ets.insert_new(segment, entry) do
				false -> :ets.insert(segment, entry)
				true ->
					if :ets.info(segment, :size) > max_per_segment do
						case purger do
							:blocking ->
								:ets.delete_all_objects(segment)
								:ets.insert_new(segment, entry) # re-insert this one we just inserted
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

		def take(key, {segments, _max_per_segment, _purger}) do
			segment = segment_for_key(key, segments)
			case :ets.take(segment, key) do
				[] -> nil
				[item] -> {:ok, item}
			end
		end

		def expires(key, {segments, _max_per_segment, _purger}) do
			segment = segment_for_key(key, segments)
			case :ets.lookup(segment, key) do
				[{_, _, expires}] -> expires
				_ -> nil
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
			reduce_segments(segments, 0, fn segment, count ->
				count + :ets.info(segment, :size)
			end)
		end

		def reduce_segments(segments, acc, fun) do
			Enum.reduce(0..tuple_size(segments)-1, acc, fn i, acc ->
				fun.(elem(segments, i), acc)
			end)
		end
	end
end
