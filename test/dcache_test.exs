defmodule DCache.Tests.DCache do
	use DCache.Tests
	alias DCache.Tests.Cache.Users, as: UserCache
	alias DCache.Tests.Cache.Products, as: ProductCache

	setup_all do
		:ok = UserCache.setup()
		:ok = ProductCache.setup()
		:ok = DCache.setup(:users, 100, purger: :no_spawn)
		:ok = DCache.setup(:products, 10, segments: 2, purger: &DCache.Tests.Cache.custom_purger/1)
		:ok
	end

	setup do
		UserCache.clear()
		ProductCache.clear()
		DCache.clear(:users)
		DCache.clear(:products)
		:ok
	end

	describe "defined" do
		test "get / put / ttl" do
			assert UserCache.get("k") == nil
			assert UserCache.ttl("k") == nil

			assert UserCache.put("k", 1, 10) == :ok
			assert UserCache.get("k") == {:ok, 1}
			assert UserCache.ttl("k") == 10

			assert UserCache.put("k", 2, 12) == :ok
			assert UserCache.get("k") == {:ok, 2}
			assert UserCache.ttl("k") == 12

			assert UserCache.put("stale", 3, -10) == :ok
			assert UserCache.ttl("stale") == -10
			assert UserCache.get("stale") == nil
			assert UserCache.ttl("stale") == nil
		end

		test "fetch" do
			assert UserCache.put("fetch", 4, 10) == :ok
			assert UserCache.fetch("fetch", nil, 100) == {:ok, 4}

			assert UserCache.put("fetch", 5, -10) == :ok
			assert UserCache.fetch!("fetch", fn key ->
				{:ok, key <> "x"}
			end, 100) == "fetchx"
			assert UserCache.get("fetch") == {:ok, "fetchx"}

			assert UserCache.fetch("fetch2", fn _key ->
				{:skip, "nope"}
			end, 100) == "nope"
			assert UserCache.get("fetch2") == nil

			assert UserCache.fetch("fetch3", fn _key ->
				{:error, "nope2"}
			end, 100) == {:error, "nope2"}
			assert UserCache.get("fetch3") == nil

			assert UserCache.fetch("fetch4", fn _key ->
				{:ok, "explicit ttl", 5}
			end, nil) == {:ok, "explicit ttl"}
			assert_in_delta UserCache.ttl("fetch4"), 5, 1

			assert_raise RuntimeError, fn ->
				UserCache.fetch!("fail", fn _key -> {:error, "fail"} end)
			end

			assert UserCache.fetch!("key3", fn key -> {:skip, "other:#{key}"} end) == "other:key3"
		end

		test "del" do
			assert UserCache.del("del") == :ok

			assert UserCache.put("del", "a", 10) == :ok
			assert UserCache.get("del") == {:ok, "a"}

			assert UserCache.del("del") == :ok
			assert UserCache.get("del") == nil
		end

		test "take" do
			assert UserCache.take("take") == nil

			assert UserCache.put("take", "b", 10) == :ok
			assert UserCache.get("take") == {:ok, "b"}

			assert {:ok, entry} = UserCache.take("take")
			assert_in_delta DCache.Entry.ttl(entry), 10, 1
			assert UserCache.get("take") == nil
		end

		test "purge on put" do
			for i <- 1..1001 do
				assert UserCache.put(to_string(i), i, 100) == :ok
			end
			assert UserCache.size() < 950
		end

		test "custom purger" do
			for i <- 1..100 do
				assert ProductCache.put(to_string(i), i, 100) == :ok
			end
			assert :ets.lookup(DCache.Tests.Cache.Products0, :purger) == [purger: 51]
			assert :ets.lookup(DCache.Tests.Cache.Products1, :purger) == [purger: 41]
		end
	end

	describe "dynamic" do
		test "get / put / ttl" do
			assert DCache.get(:users, "k") == nil
			assert DCache.ttl(:users, "k") == nil

			assert DCache.put(:users, "k", 1, 10) == :ok
			assert DCache.get(:users, "k") == {:ok, 1}
			assert DCache.ttl(:users, "k") == 10

			assert DCache.put(:users, "k", 2, 12) == :ok
			assert DCache.get(:users, "k") == {:ok, 2}
			assert DCache.ttl(:users, "k") == 12

			assert DCache.put(:users, "stale", 3, -10) == :ok
			assert DCache.ttl(:users, "stale") == -10
			assert DCache.get(:users, "stale") == nil
			assert DCache.ttl(:users, "stale") == nil
		end

		test "fetch" do
			assert DCache.put(:users, "fetch", 4, 10) == :ok
			assert DCache.fetch(:users, "fetch", nil, 100) == {:ok, 4}

			assert DCache.put(:users, "fetch", 5, -10) == :ok
			assert DCache.fetch!(:users, "fetch", fn key ->
				{:ok, key <> "x"}
			end, 100) == "fetchx"
			assert DCache.get(:users, "fetch") == {:ok, "fetchx"}

			assert DCache.fetch(:users, "fetch2", fn _key ->
				{:skip, "nope"}
			end, 100) == "nope"
			assert DCache.get(:users, "fetch2") == nil

			assert DCache.fetch(:users, "fetch3", fn _key ->
				{:error, "nope2"}
			end, 100) == {:error, "nope2"}
			assert DCache.get(:users, "fetch3") == nil

			assert DCache.fetch(:users, "fetch4", fn _key ->
				{:ok, "explicit ttl", 5}
			end, nil) == {:ok, "explicit ttl"}
			assert_in_delta DCache.ttl(:users, "fetch4"), 5, 1

			assert_raise RuntimeError, fn ->
				DCache.fetch!(:users, "fail", fn _key -> {:error, "fail"} end)
			end

			assert DCache.fetch!(:users, "key3", fn key -> {:skip, "other:#{key}"} end) == "other:key3"
		end

		test "del" do
			assert DCache.del(:users, "del") == :ok

			assert DCache.put(:users, "del", "a", 10) == :ok
			assert DCache.get(:users, "del") == {:ok, "a"}

			assert DCache.del(:users, "del") == :ok
			assert DCache.get(:users, "del") == nil
		end

		test "take" do
			assert DCache.take(:users, "take") == nil

			assert DCache.put(:users, "take", "b", 10) == :ok
			assert DCache.get(:users, "take") == {:ok, "b"}

			assert {:ok, entry} = DCache.take(:users, "take")
			assert_in_delta DCache.Entry.ttl(entry), 10, 1
			assert DCache.get(:users, "take") == nil
		end

		test "purge on put" do
			for i <- 1..1001 do
				assert DCache.put(:users, to_string(i), i, 100) == :ok
			end
			assert DCache.size(:users) < 950
		end

		test "custom purger" do
			for i <- 1..100 do
				assert DCache.put(:products, to_string(i), i, 100) == :ok
			end
			assert :ets.lookup(:products0, :purger) == [purger: 51]
			assert :ets.lookup(:products1, :purger) == [purger: 41]
		end

		test "destroy" do
			DCache.setup(:temp, 100)
			DCache.put(:temp, "a", 1, 100)
			DCache.destroy(:temp)
			assert_raise ArgumentError, fn -> DCache.get(:temp, "a") end
		end
	end

	describe "purgers" do
		test "expiration-based" do
			DCache.setup(:c1, 1_000, segments: 5, purger: :default)
			DCache.setup(:c2, 1_000, segments: 5, purger: :no_spawn)
			Enum.each(1..1001, fn i ->
				ttl = case rem(i, 2) do
					0 -> 10
					1 -> -10
				end
				DCache.put(:c1, i, i, ttl)
				DCache.put(:c2, i, i, ttl)
			end)

			# we don't know for sure what happened, but we do know:
			# A - Some items should have been purged
			# B - Only expired items should have been purged
			#     (Or, inversely, no non-expired items should have been purged)

			assert DCache.size(:c1) < 900
			assert DCache.size(:c2) < 900

			Enum.each(1..1001, fn i ->
				if rem(i, 2) == 0 do
					assert DCache.get(:c1, i) == {:ok, i}
					assert DCache.get(:c2, i) == {:ok, i}
				end
			end)
		end

		test "random-based" do
			DCache.setup(:c1, 1_000, segments: 5, purger: :default)
			DCache.setup(:c2, 1_000, segments: 5, purger: :no_spawn)
			Enum.each(1..1001, fn i ->
				DCache.put(:c1, i, i, 10)
				DCache.put(:c2, i, i, 10)
			end)

			# we don't know for sure what happened, but we do know
			# that some items, even though they aren't expired, should have been purged
			assert DCache.size(:c1) < 900
			assert DCache.size(:c2) < 900
		end

		test "none purger" do
			DCache.setup(:c3, 10, segments: 2, purger: :none)
			Enum.each(1..100, fn i ->
				DCache.put(:c3, i, i, 10)
			end)

			assert DCache.size(:c3) == 100

			# let's make absolutely sure
			Enum.each(1..100, fn i ->
				assert DCache.get(:c3, i) == {:ok, i}
			end)
		end
	end

	test "entry" do

		assert DCache.Entry.key(nil) == nil
		assert DCache.Entry.value(nil) == nil
		assert DCache.Entry.ttl(nil) == nil
		assert DCache.Entry.expiry(nil) == nil

		UserCache.put("goku", 9001, 100)
		{:ok, entry} = UserCache.entry("goku")

		assert DCache.Entry.key(entry) == "goku"
		assert DCache.Entry.value(entry) == 9001
		assert DCache.Entry.ttl(entry) == 100
		assert DCache.Entry.expiry(entry) - :erlang.monotonic_time(:second) == 100
	end
end
